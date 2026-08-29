import '../utils/types.dart';

class QuarkUserInfo {
  final String nickname;
  final String avatar;
  final String userId;

  /// 总容量（字节），0 表示未返回
  final int totalSpace;

  /// 已用容量（字节）
  final int usedSpace;

  QuarkUserInfo({
    required this.nickname,
    required this.avatar,
    required this.userId,
    this.totalSpace = 0,
    this.usedSpace = 0,
  });

  factory QuarkUserInfo.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map) {
      return QuarkUserInfo(
        nickname: _s(data, 'nickname'),
        avatar: _s(data, 'avatar'),
        userId: _s(data, 'user_id'),
      );
    }
    return QuarkUserInfo(
      nickname: _s(json, 'nickname'),
      avatar: _s(json, 'avatar'),
      userId: _s(json, 'user_id'),
    );
  }

  /// 返回带容量信息的新实例（容量来自 /1/clouddrive/member 接口）
  /// [total] 总容量（字节），[used] 已用容量（字节）
  QuarkUserInfo withCapacity(int total, int used) => QuarkUserInfo(
        nickname: nickname,
        avatar: avatar,
        userId: userId,
        totalSpace: total,
        usedSpace: used,
      );

  static String _s(dynamic obj, String key) {
    if (obj is Map) {
      final v = obj[key];
      return v == null ? '' : v.toString();
    }
    return '';
  }
}

class QuarkFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String fileExt;
  final int updatedAt;
  final int category;
  final String objCategory;
  final String thumbnail;
  final String bigThumbnail;
  final String previewUrl;
  final int duration;

  QuarkFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.fileExt,
    required this.updatedAt,
    required this.category,
    required this.objCategory,
    required this.thumbnail,
    required this.bigThumbnail,
    required this.previewUrl,
    required this.duration,
  });

  bool get isImage =>
      objCategory == 'image' ||
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
          .contains(fileExt.toLowerCase());

  /// 动态照片（手机 live photo，短时长视频片段）
  bool get isLivePhoto =>
      !isDir &&
      (objCategory == 'video' || fileExt.toLowerCase() == 'mp4') &&
      duration > 0 &&
      duration <= 15000;

  factory QuarkFile.fromJson(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? '';
    final dirFlag = json['dir'] == true;
    return QuarkFile(
      fid: json['fid']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: toInt(json['size']),
      pdirFid: json['pdir_fid']?.toString() ?? '',
      fileExt: json['file_ext']?.toString() ?? '',
      updatedAt: toInt(json['updated_at']),
      category: toInt(json['category']),
      objCategory: json['obj_category']?.toString() ?? '',
      thumbnail:
          json['thumbnail']?.toString() ?? json['preview_url']?.toString() ?? json['cover']?.toString() ?? '',
      bigThumbnail: json['big_thumbnail']?.toString() ?? '',
      previewUrl: json['preview_url']?.toString() ?? '',
      duration: toInt(json['duration']),
    );
  }
}

class QuarkShareFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String shareFidToken;

  QuarkShareFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.shareFidToken,
  });

  factory QuarkShareFile.fromJson(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? '';
    final dirFlag = json['dir'] == true;
    return QuarkShareFile(
      fid: json['fid']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: toInt(json['size']),
      pdirFid: json['pdir_fid']?.toString() ?? '',
      shareFidToken: json['share_fid_token']?.toString() ?? '',
    );
  }
}

class QuarkDownloadInfo {
  final String url;
  final String fileName;
  final int size;
  final String fid;

  QuarkDownloadInfo({
    required this.url,
    required this.fileName,
    required this.size,
    required this.fid,
  });

  factory QuarkDownloadInfo.fromJson(Map<String, dynamic> json) {
    return QuarkDownloadInfo(
      url: json['download_url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      size: toInt(json['size']),
      fid: json['fid']?.toString() ?? '',
    );
  }
}

/// 夸克上传会话（/file/upload/pre 响应，协议对齐 alist quark_uc 驱动）
class QuarkUploadSession {
  /// 上传任务 id（hash 校验与 finish 使用）
  final String taskId;

  /// 服务端秒传命中（无需分片上传）
  final bool finish;

  /// OSS 分片上传参数
  final String uploadId;
  final String objKey;
  final String uploadUrl;
  final String bucket;
  final String authInfo;

  /// OSS 回调（合并完成后服务端回调网盘登记文件）
  final String callbackUrl;
  final String callbackBody;

  /// 服务端建议分片大小（字节）
  final int partSize;

  /// 预申请后服务端已登记的 fid（秒传/完成场景可能返回）
  final String fid;

  QuarkUploadSession({
    required this.taskId,
    required this.finish,
    required this.uploadId,
    required this.objKey,
    required this.uploadUrl,
    required this.bucket,
    required this.authInfo,
    required this.callbackUrl,
    required this.callbackBody,
    required this.partSize,
    required this.fid,
  });

  factory QuarkUploadSession.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final callback = data is Map ? data['callback'] : null;
    return QuarkUploadSession(
      taskId: _str(data, 'task_id'),
      finish: data is Map && data['finish'] == true,
      uploadId: _str(data, 'upload_id'),
      objKey: _str(data, 'obj_key'),
      uploadUrl: _str(data, 'upload_url'),
      bucket: _str(data, 'bucket'),
      authInfo: _str(data, 'auth_info'),
      callbackUrl: _str(callback, 'callbackUrl'),
      callbackBody: _str(callback, 'callbackBody'),
      partSize: toInt(json['metadata']?['part_size'], fallback: 0),
      fid: _str(data, 'fid'),
    );
  }

  static String _str(dynamic obj, String key) {
    if (obj is Map) {
      final v = obj[key];
      return v == null ? '' : v.toString();
    }
    return '';
  }
}
