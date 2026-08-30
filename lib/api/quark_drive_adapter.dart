import 'base_drive.dart';
import 'drive_type.dart';
import 'quark_client.dart';
import 'quark_models.dart';

/// 将 QuarkClient 包装为 BaseDrive，使 ShareFilesPage 等通用组件可以统一使用
class QuarkDriveAdapter extends BaseDrive {
  final QuarkClient _client;

  QuarkDriveAdapter(this._client);

  @override
  DriveType get type => DriveType.quark;

  @override
  String get label => '夸克网盘';

  @override
  bool get hasLogin => _client.hasLogin;

  @override
  DriveUserInfo? get userInfo {
    // 通过 AppState 获取用户信息，这里简化处理
    return null;
  }

  @override
  Future<void> init() async {}

  @override
  Future<String?> login(dynamic credential) async {
    return '暂不支持此方式登录';
  }

  @override
  Future<void> logout() async {
    _client.setCookie('');
  }

  @override
  Future<void> refreshUser() async {}

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final files = await _client.listFiles(pdirFid, page: page, size: size);
    return files.map((f) => DriveFile(
      fid: f.fid,
      fileName: f.fileName,
      fileType: f.fileType,
      isDir: f.isDir,
      size: f.size,
      pdirFid: f.pdirFid,
      fileExt: f.fileExt,
      updatedAt: f.updatedAt,
      thumbnail: f.thumbnail,
      previewUrl: f.previewUrl,
    )).toList();
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    return [];
  }

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    final (infos, _) = await _client.getDownloadInfo(fids);
    return infos.map((i) => DriveDownloadInfo(
      url: i.url,
      fileName: i.fileName,
      size: i.size,
      fid: i.fid,
    )).toList();
  }

  @override
  Future<DriveShareSession> getShareToken(
      String pwdId, String passcode) async {
    final session = await _client.getShareToken(pwdId, passcode);
    return DriveShareSession(
      shareId: session.shareId,
      pwdId: session.pwdId,
      passcode: session.passcode,
      stoken: session.stoken,
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(
      DriveShareSession session, String pdirFid,
      {int page = 1, int size = 50}) async {
    final qs = QuarkShareSession(
      pwdId: session.pwdId,
      passcode: session.passcode,
      shareId: session.shareId,
      stoken: session.stoken,
    );
    final files = await _client.listShare(qs, pdirFid, page: page, size: size);
    return files.map((f) => DriveShareFile(
      fid: f.fid,
      fileName: f.fileName,
      fileType: f.fileType,
      isDir: f.isDir,
      size: f.size,
      pdirFid: f.pdirFid,
      shareFidToken: f.shareFidToken,
    )).toList();
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    final qs = QuarkShareSession(
      pwdId: session.pwdId,
      passcode: session.passcode,
      shareId: session.shareId,
      stoken: session.stoken,
    );
    final infos = await _client.getShareDownloadInfo(qs, fidList);
    return infos.map((i) => DriveDownloadInfo(
      url: i.url,
      fileName: i.fileName,
      size: i.size,
      fid: i.fid,
    )).toList();
  }

  @override
  Future<void> saveShare(DriveShareSession session,
      List<DriveShareFile> files, String toPdirFid) async {
    final qs = QuarkShareSession(
      pwdId: session.pwdId,
      passcode: session.passcode,
      shareId: session.shareId,
      stoken: session.stoken,
    );
    final qFiles = files.map((f) => QuarkShareFile(
      fid: f.fid,
      fileName: f.fileName,
      fileType: f.fileType,
      isDir: f.isDir,
      size: f.size,
      pdirFid: f.pdirFid,
      shareFidToken: f.shareFidToken,
    )).toList();
    await _client.saveShare(qs, qFiles, toPdirFid);
  }

  @override
  bool get supportsRename => true;

  @override
  bool get supportsMove => true;

  @override
  bool get supportsShare => true;

  @override
  Future<DriveShareResult> shareFiles(List<String> fids) async {
    final r = await _client.shareFiles(fids);
    return DriveShareResult(url: r.url, pwd: r.pwd, surl: r.pwdId);
  }

  @override
  Future<String?> renameFile(String fid, String newName) =>
      _client.renameFile(fid, newName);

  @override
  Future<String?> moveFiles(List<String> fids, String toPdirFid) =>
      _client.moveFiles(fids, toPdirFid);

  @override
  void dispose() {}
}