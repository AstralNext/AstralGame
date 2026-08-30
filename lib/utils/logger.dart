import 'package:logger/logger.dart';

/// 默认关闭输出，避免单测未装配 logger 时刷屏。
Logger appLogger = Logger(
  level: Level.off,
  printer: SimplePrinter(colors: false),
);

void setAppLogger(Logger logger) {
  appLogger = logger;
}
