use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use windows::core::{GUID, PWSTR};
use windows::Win32::NetworkManagement::IpHelper::{
    ConvertInterfaceGuidToLuid, FreeInterfaceDnsSettings, GetIfEntry2, GetInterfaceDnsSettings,
    SetInterfaceDnsSettings, DNS_INTERFACE_SETTINGS, DNS_INTERFACE_SETTINGS_VERSION1,
    DNS_SETTING_IPV6, DNS_SETTING_NAMESERVER, MIB_IF_ROW2,
};
use windows::Win32::NetworkManagement::Ndis::{
    NdisPhysicalMedium802_3, NdisPhysicalMediumBluetooth, NdisPhysicalMediumNative802_11,
    NdisPhysicalMediumOther, NdisPhysicalMediumUnspecified, NdisPhysicalMediumWirelessLan,
    NET_IF_ACCESS_BROADCAST, NET_IF_ACCESS_LOOPBACK, NET_IF_ACCESS_POINT_TO_POINT,
    NET_IF_CONNECTION_DEMAND, NET_LUID_LH, TUNNEL_TYPE_NONE,
};

use crate::log;

/// 辅助 DNS（主 DNS 用网卡自身地址）。IPv4 / IPv6 必须分两次写入。
const DNS_V4_ALT: &str = "119.29.29.29";
const DNS_V6_ALT: &str = "2402:4e00::";

const IF_TYPE_ETHERNET_CSMACD: u32 = 6;
const IF_TYPE_IEEE80211: u32 = 71;

/// MIB_IF_ROW2.InterfaceAndOperStatusFlags bit layout from netioapi.h
const FLAG_HARDWARE: u8 = 1 << 0;
const FLAG_FILTER: u8 = 1 << 1;
const FLAG_CONNECTOR: u8 = 1 << 2;
const FLAG_ENDPOINT: u8 = 1 << 7;

#[link(name = "dnsapi")]
extern "system" {
    fn DnsFlushResolverCache() -> i32;
}

pub type AdapterState = HashMap<String, (String, Vec<IpAddr>)>;

fn parse_guid(guid_str: &str) -> Option<GUID> {
    let clean = guid_str.trim_matches(|c| c == '{' || c == '}');
    uuid::Uuid::parse_str(clean)
        .ok()
        .map(|parsed| GUID::from_u128(parsed.as_u128()))
}

fn query_if_row(adapter: &ipconfig::Adapter) -> Option<MIB_IF_ROW2> {
    unsafe {
        if adapter.ipv6_if_index() != 0 {
            let mut row = MIB_IF_ROW2 {
                InterfaceIndex: adapter.ipv6_if_index(),
                ..MIB_IF_ROW2::default()
            };
            if GetIfEntry2(&mut row).is_ok() {
                return Some(row);
            }
        }

        let guid = parse_guid(adapter.adapter_name())?;
        let mut luid = NET_LUID_LH::default();
        ConvertInterfaceGuidToLuid(&guid, &mut luid).ok()?;
        let mut row = MIB_IF_ROW2 {
            InterfaceLuid: luid,
            ..MIB_IF_ROW2::default()
        };
        GetIfEntry2(&mut row).ok()?;
        Some(row)
    }
}

fn mac_usable(row: &MIB_IF_ROW2) -> bool {
    let len = row.PhysicalAddressLength as usize;
    if len < 6 {
        return false;
    }
    let mac = &row.PhysicalAddress[..len.min(row.PhysicalAddress.len())];
    !mac.iter().all(|&b| b == 0)
}

/// 用内核 MIB_IF_ROW2 判断，而不是网卡名字里有没有 "virtual"。
fn is_physical_nic(row: &MIB_IF_ROW2) -> bool {
    let flags = row.InterfaceAndOperStatusFlags._bitfield;
    if flags & FLAG_FILTER != 0 || flags & FLAG_ENDPOINT != 0 {
        return false;
    }
    if flags & FLAG_HARDWARE == 0 {
        return false;
    }
    if row.TunnelType != TUNNEL_TYPE_NONE {
        return false;
    }
    if row.AccessType == NET_IF_ACCESS_LOOPBACK || row.AccessType == NET_IF_ACCESS_POINT_TO_POINT {
        return false;
    }
    if row.ConnectionType == NET_IF_CONNECTION_DEMAND {
        return false;
    }
    if row.Type != IF_TYPE_ETHERNET_CSMACD && row.Type != IF_TYPE_IEEE80211 {
        return false;
    }
    let medium = row.PhysicalMediumType.0;
    if medium == NdisPhysicalMediumBluetooth.0 {
        return false;
    }
    if !mac_usable(row) {
        return false;
    }

    let medium_ok = medium == NdisPhysicalMedium802_3.0
        || medium == NdisPhysicalMediumNative802_11.0
        || medium == NdisPhysicalMediumWirelessLan.0;
    if medium_ok {
        return true;
    }

    // USB 有线网卡经常报 Unspecified/Other；有连接器 + 硬件标志才收。
    let maybe_usb = medium == NdisPhysicalMediumUnspecified.0
        || medium == NdisPhysicalMediumOther.0;
    maybe_usb && flags & FLAG_CONNECTOR != 0 && row.AccessType == NET_IF_ACCESS_BROADCAST
}

pub fn get_all_physical_ips() -> Option<AdapterState> {
    let mut result = AdapterState::new();
    let adapters = ipconfig::get_adapters().unwrap_or_default();

    for adapter in adapters {
        if adapter.oper_status() != ipconfig::OperStatus::IfOperStatusUp {
            continue;
        }

        let Some(row) = query_if_row(&adapter) else {
            continue;
        };
        if !is_physical_nic(&row) {
            continue;
        }

        let guid = adapter.adapter_name().to_string();
        let friendly_name = adapter.friendly_name().to_string();
        let ips = pick_bind_ips(adapter.ip_addresses());
        if !ips.is_empty() {
            result.insert(guid, (friendly_name, ips));
        }
    }

    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

fn is_usable_v4(ip: Ipv4Addr) -> bool {
    !ip.is_unspecified() && !ip.is_loopback() && !ip.is_link_local() && !ip.is_multicast()
}

fn is_usable_v6(ip: Ipv6Addr) -> bool {
    !ip.is_unspecified() && !ip.is_loopback() && !ip.is_multicast()
}

fn pick_v4(ips: &[IpAddr]) -> Option<IpAddr> {
    ips.iter().copied().find(|ip| match ip {
        IpAddr::V4(v) => is_usable_v4(*v),
        IpAddr::V6(_) => false,
    })
}

fn pick_v6(ips: &[IpAddr]) -> Option<IpAddr> {
    // 主 DNS 用「本地链接 IPv6」（fe80::），写入时不含 %zone。
    let link_local = ips.iter().copied().find(|ip| match ip {
        IpAddr::V6(v) => is_usable_v6(*v) && v.is_unicast_link_local(),
        IpAddr::V4(_) => false,
    });
    link_local.or_else(|| {
        ips.iter().copied().find(|ip| match ip {
            IpAddr::V6(v) => is_usable_v6(*v) && !v.is_unicast_link_local(),
            IpAddr::V4(_) => false,
        })
    })
}

fn pick_bind_ips(ips: &[IpAddr]) -> Vec<IpAddr> {
    let mut out = Vec::new();
    if let Some(v4) = pick_v4(ips) {
        out.push(v4);
    }
    if let Some(v6) = pick_v6(ips) {
        out.push(v6);
    }
    out
}

/// Windows 会显示 `fe80::…%20`；写入 DNS 时去掉 `%` 及后面的区域 ID。
fn strip_zone_id(s: &str) -> &str {
    s.split_once('%').map(|(addr, _)| addr).unwrap_or(s)
}

fn format_ip_for_dns(ip: IpAddr) -> String {
    strip_zone_id(&ip.to_string()).to_string()
}

fn nameserver_list(primary: IpAddr, alt: &str) -> String {
    format!("{},{}", format_ip_for_dns(primary), strip_zone_id(alt))
}

pub fn bind_local_smartdns(guid_str: &str, ips: &[IpAddr]) {
    let mut wrote = false;
    if let Some(v4) = pick_v4(ips) {
        wrote |= set_nameservers(guid_str, &nameserver_list(v4, DNS_V4_ALT), false);
    }
    if let Some(v6) = pick_v6(ips) {
        wrote |= set_nameservers(guid_str, &nameserver_list(v6, DNS_V6_ALT), true);
    }
    if wrote {
        flush_dns_cache();
    }
}

pub fn dns_already_bound(guid_str: &str, ips: &[IpAddr]) -> bool {
    let expected_v4 = pick_v4(ips)
        .map(|ip| parse_dns_list(&nameserver_list(ip, DNS_V4_ALT)))
        .unwrap_or_default();
    let expected_v6 = pick_v6(ips)
        .map(|ip| parse_dns_list(&nameserver_list(ip, DNS_V6_ALT)))
        .unwrap_or_default();
    let v4 = read_nameservers(guid_str, false)
        .unwrap_or_default()
        .into_iter()
        .filter(IpAddr::is_ipv4)
        .collect::<Vec<_>>();
    let v6 = read_nameservers(guid_str, true)
        .unwrap_or_default()
        .into_iter()
        .filter(IpAddr::is_ipv6)
        .collect::<Vec<_>>();
    v4 == expected_v4 && v6 == expected_v6
}

fn parse_dns_list(s: &str) -> Vec<IpAddr> {
    s.split(|c: char| c == ',' || c == ';' || c.is_whitespace())
        .filter(|token| !token.is_empty())
        .filter_map(|token| strip_zone_id(token).parse().ok())
        .collect()
}

fn read_nameservers(guid_str: &str, ipv6: bool) -> Option<Vec<IpAddr>> {
    let guid = parse_guid(guid_str)?;
    unsafe {
        let mut settings = DNS_INTERFACE_SETTINGS {
            Version: DNS_INTERFACE_SETTINGS_VERSION1,
            Flags: if ipv6 { DNS_SETTING_IPV6 as u64 } else { 0 },
            ..DNS_INTERFACE_SETTINGS::default()
        };
        GetInterfaceDnsSettings(guid, &mut settings).ok()?;
        let text = if settings.NameServer.is_null() {
            String::new()
        } else {
            settings.NameServer.to_string().unwrap_or_default()
        };
        let _ = FreeInterfaceDnsSettings(&mut settings);
        Some(parse_dns_list(&text))
    }
}

pub fn clear_all_physical_to_dhcp() {
    let Some(state) = get_all_physical_ips() else {
        return;
    };
    let mut wrote = false;
    for guid in state.keys() {
        wrote |= set_nameservers(guid, "", false);
        wrote |= set_nameservers(guid, "", true);
    }
    if wrote {
        flush_dns_cache();
    }
}

/// 与 `ipconfig /flushdns` 相同：清 DNS Client 解析缓存。
fn flush_dns_cache() {
    unsafe {
        if DnsFlushResolverCache() != 0 {
            log::info("DNS resolver cache flushed");
        } else {
            log::warn("DnsFlushResolverCache failed");
        }
    }
}

fn set_nameservers(guid_str: &str, servers: &str, ipv6: bool) -> bool {
    let mut nameservers: Vec<u16> = servers.encode_utf16().chain(std::iter::once(0)).collect();

    let Some(guid) = parse_guid(guid_str) else {
        log::error(&format!("cannot parse adapter GUID: {guid_str}"));
        return false;
    };

    let mut flags = DNS_SETTING_NAMESERVER as u64;
    if ipv6 {
        flags |= DNS_SETTING_IPV6 as u64;
    }
    let stack = if ipv6 { "IPv6" } else { "IPv4" };

    unsafe {
        let mut settings: DNS_INTERFACE_SETTINGS = std::mem::zeroed();
        settings.Version = DNS_INTERFACE_SETTINGS_VERSION1;
        settings.Flags = flags;
        settings.NameServer = PWSTR(nameservers.as_mut_ptr());

        match SetInterfaceDnsSettings(guid, &settings) {
            Ok(()) => {
                if servers.is_empty() {
                    log::info(&format!("DNS restored to DHCP ({stack}) on {guid_str}"));
                } else {
                    log::info(&format!(
                        "DNS overwritten ({stack}) to {servers} on {guid_str}"
                    ));
                }
                true
            }
            Err(err) => {
                let hr = err.code().0 as u32;
                if hr == 0x8007_0005 {
                    log::error(
                        "SetInterfaceDnsSettings access denied; run as Administrator",
                    );
                } else {
                    log::error(&format!(
                        "SetInterfaceDnsSettings {stack} failed: {err}"
                    ));
                }
                false
            }
        }
    }
}
