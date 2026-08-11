enum DriveType {
  quark,
  ali,
  baidu,
  pikpak,
  tianyi,
  uc,
  weiyun,
  xunlei,
  pan123,
  yidong,
  guangya;

  String get label {
    switch (this) {
      case DriveType.quark:
        return '夸克网盘';
      case DriveType.ali:
        return '阿里云盘';
      case DriveType.baidu:
        return '百度网盘';
      case DriveType.pikpak:
        return 'PikPak';
      case DriveType.tianyi:
        return '天翼云盘';
      case DriveType.uc:
        return 'UC网盘';
      case DriveType.weiyun:
        return '微云';
      case DriveType.xunlei:
        return '迅雷网盘';
      case DriveType.pan123:
        return '123云盘';
      case DriveType.yidong:
        return '移动云盘';
      case DriveType.guangya:
        return '光丫';
    }
  }

  String get iconAsset {
    switch (this) {
      case DriveType.quark:
        return 'assets/icons/quark.png';
      case DriveType.ali:
        return 'assets/icons/ali.png';
      case DriveType.baidu:
        return 'assets/icons/baidu.png';
      case DriveType.pikpak:
        return 'assets/icons/pikpak.png';
      case DriveType.tianyi:
        return 'assets/icons/tianyi.png';
      case DriveType.uc:
        return 'assets/icons/uc.png';
      case DriveType.weiyun:
        return 'assets/icons/weiyun.png';
      case DriveType.xunlei:
        return 'assets/icons/xunlei.png';
      case DriveType.pan123:
        return 'assets/icons/123.png';
      case DriveType.yidong:
        return 'assets/icons/yidong.png';
      case DriveType.guangya:
        return 'assets/icons/quark.png';
    }
  }

  static DriveType detectFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('quark.cn') || u.contains('pan.quark')) return DriveType.quark;
    if (u.contains('aliyundrive') || u.contains('alipan') || u.contains('aliyun.com/s')) return DriveType.ali;
    if (u.contains('pan.baidu.com') || u.contains('yun.baidu.com')) return DriveType.baidu;
    if (u.contains('mypikpak.com') || u.contains('pikpak')) return DriveType.pikpak;
    if (u.contains('cloud.189.cn') || u.contains('189.cn')) return DriveType.tianyi;
    if (u.contains('uc.cn') || u.contains('drive.uc')) return DriveType.uc;
    if (u.contains('weiyun.com')) return DriveType.weiyun;
    if (u.contains('xunlei.com') || u.contains('pan.xunlei')) return DriveType.xunlei;
    if (u.contains('123pan.cn') || u.contains('123pan.com') || u.contains('123.cn')) return DriveType.pan123;
    if (u.contains('139.com') || u.contains('caiyun.139')) return DriveType.yidong;
    if (u.contains('guangyapan.com')) return DriveType.guangya;
    return DriveType.quark;
  }
}