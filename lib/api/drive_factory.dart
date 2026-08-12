import 'base_drive.dart';
import 'drive_type.dart';

/// 网盘驱动工厂
class DriveFactory {
  static BaseDrive? _create(DriveType type) {
    switch (type) {
      case DriveType.quark:
        return null; // 使用原有的 QuarkClient
      case DriveType.ali:
        return null;
      case DriveType.baidu:
        return null;
      case DriveType.pikpak:
        return null;
      case DriveType.tianyi:
        return null;
      case DriveType.uc:
        return null;
      case DriveType.weiyun:
        return null;
      case DriveType.xunlei:
        return null;
      case DriveType.pan123:
        return null;
      case DriveType.yidong:
        return null;
      case DriveType.guangya:
        return null;
      case DriveType.lanzou:
        return null;
    }
  }
}