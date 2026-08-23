#![cfg_attr(not(windows), allow(dead_code))]

mod log;
mod paths;

#[cfg(windows)]
mod ctl;
#[cfg(windows)]
mod dns;
#[cfg(windows)]
mod smartdns;
#[cfg(windows)]
mod svc;
#[cfg(windows)]
mod watch;

fn print_help() {
    println!(
        "Astral Game Auto DNS Binder

封装 SmartDNS 服务安装，并把物理网卡 DNS 绑到本机。

Usage: auto_dns_binder.exe <COMMAND>

Commands:
  install      安装 SmartDNS + DNS 绑定服务（需管理员）
  uninstall    卸载上述服务并恢复自动 DNS
  start        启动 DNS 绑定服务
  stop         停止 DNS 绑定服务
  restart      重启 DNS 绑定服务
  status       查看服务状态
  help         显示帮助

Service name: {}
Install dir:  {}",
        paths::SERVICE_NAME,
        paths::program_data_dir().display()
    );
}

fn main() {
    #[cfg(not(windows))]
    {
        eprintln!("auto_dns_binder 仅支持 Windows");
        std::process::exit(1);
    }

    #[cfg(windows)]
    {
        let args: Vec<String> = std::env::args().skip(1).collect();
        if args.is_empty() {
            match svc::run_dispatcher() {
                Ok(()) => return,
                Err(err) => {
                    eprintln!("{err}");
                    print_help();
                    std::process::exit(1);
                }
            }
        }

        let cmd = args[0].as_str();
        if matches!(cmd, "help" | "-h" | "--help") {
            print_help();
            return;
        }
        if cmd != "status" {
            log::init(paths::log_file());
        }
        let result = match cmd {
            "install" => ctl::install(),
            "uninstall" => ctl::uninstall(),
            "start" => ctl::start(),
            "stop" => ctl::stop(),
            "restart" => ctl::restart(),
            "status" => ctl::status(),
            other => {
                eprintln!("unknown command: {other}\n");
                print_help();
                std::process::exit(2);
            }
        };
        if let Err(err) = result {
            log::error(&err);
            std::process::exit(1);
        }
    }
}
