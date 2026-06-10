import { picker, fileIo } from '@kit.CoreFileKit';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG: string = 'PetNoteDataPackageFileAccessPlugin';
const CHANNEL_NAME: string = 'petnote/data_package_file_access';
const BACKUP_DIR_NAME: string = 'backups';
const DEFAULT_PICK_NAME: string = 'backup.json';

export default class PetNoteDataPackageFileAccessPlugin
  implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pluginBinding: FlutterPluginBinding | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
      StandardMethodCodec.INSTANCE,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.pluginBinding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'pickBackupFile':
        this.handlePickBackupFile(result);
        break;
      case 'saveBackupFile':
        this.handleSaveBackupFile(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  // ── pickBackupFile ────────────────────────────────────────────────────

  private async handlePickBackupFile(result: MethodResult): Promise<void> {
    try {
      const context = this.pluginBinding?.getApplicationContext();
      if (context == null) {
        result.success(this.buildErrorResponse(
          'unavailable', 'Application context is not available.'
        ));
        return;
      }

      // Open system document picker filtered to JSON files
      const documentPicker = new picker.DocumentViewPicker(context);
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.maxSelectNumber = 1;
      selectOptions.fileSuffixFilters = ['.json'];

      const selectResult = await documentPicker.select(selectOptions);
      if (selectResult == null || selectResult.length === 0) {
        result.success({ 'status': 'cancelled' });
        return;
      }

      const fileUri: string = selectResult[0];
      if (fileUri == null || fileUri.length === 0) {
        result.success({ 'status': 'cancelled' });
        return;
      }

      // Copy selected file into app sandbox
      const localPath = this.copyUriToSandbox(fileUri);
      if (localPath == null) {
        result.success(this.buildErrorResponse(
          'readFailed', 'Failed to read the selected backup file.'
        ));
        return;
      }

      // Read JSON text from the sandbox copy
      const rawJson: string = fileIo.readTextSync(localPath);
      const stat = fileIo.statSync(localPath);
      const byteLength: number = stat.size;

      const displayName: string = this.getDisplayName(fileUri) ?? DEFAULT_PICK_NAME;

      const response: Record<string, Object> = {};
      response['status'] = 'success';
      response['displayName'] = displayName;
      response['rawJson'] = rawJson;
      response['locationLabel'] = localPath;
      response['byteLength'] = byteLength;
      result.success(response);
    } catch (error) {
      const message: string = this.describeError(error);
      // User dismissed the picker
      if (message.indexOf('cancel') >= 0 || message.indexOf('Cancel') >= 0) {
        result.success({ 'status': 'cancelled' });
        return;
      }
      result.success(this.buildErrorResponse('platformError', message));
    }
  }

  // ── saveBackupFile ────────────────────────────────────────────────────

  private async handleSaveBackupFile(
    call: MethodCall,
    result: MethodResult,
  ): Promise<void> {
    try {
      const sourceFilePathVal: Object | null = call.argument('sourceFilePath');
      const suggestedFileNameVal: Object | null = call.argument('suggestedFileName');

      if (typeof sourceFilePathVal !== 'string' || (sourceFilePathVal as string).length === 0) {
        result.success(this.buildErrorResponse(
          'writeFailed', 'sourceFilePath is missing or invalid.'
        ));
        return;
      }

      const sourceFilePath: string = sourceFilePathVal as string;
      const suggestedFileName: string =
        (typeof suggestedFileNameVal === 'string' && (suggestedFileNameVal as string).length > 0)
          ? (suggestedFileNameVal as string)
          : 'petnote-backup.json';

      const context = this.pluginBinding?.getApplicationContext();
      if (context == null) {
        result.success(this.buildErrorResponse(
          'unavailable', 'Application context is not available.'
        ));
        return;
      }

      // Create persistent backup directory inside app sandbox
      const backupDir: string = context.filesDir + '/' + BACKUP_DIR_NAME;
      if (!fileIo.accessSync(backupDir)) {
        fileIo.mkdirSync(backupDir, true);
      }

      const safeName: string = this.sanitizeFileName(suggestedFileName);
      const timestamp: number = Date.now();
      const targetFileName: string = timestamp.toString() + '_' + safeName;
      const targetPath: string = backupDir + '/' + targetFileName;

      // Copy the Dart-written temp file to our backup directory
      const srcFd = fileIo.openSync(sourceFilePath, fileIo.OpenMode.READ_ONLY);
      const dstFd = fileIo.openSync(
        targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE,
      );
      fileIo.copyFileSync(srcFd.fd, dstFd.fd);
      fileIo.closeSync(srcFd.fd);
      fileIo.closeSync(dstFd.fd);

      const displayName: string = safeName;
      const locationLabel: string = targetPath;
      const stat = fileIo.statSync(targetPath);
      const byteLength: number = stat.size;

      const response: Record<string, Object> = {};
      response['status'] = 'success';
      response['displayName'] = displayName;
      response['locationLabel'] = locationLabel;
      response['byteLength'] = byteLength;
      result.success(response);
    } catch (error) {
      result.success(this.buildErrorResponse('writeFailed', this.describeError(error)));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  private copyUriToSandbox(sourceUri: string): string | null {
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      return null;
    }
    try {
      const importsDir: string = context.filesDir + '/petnote_imports';
      if (!fileIo.accessSync(importsDir)) {
        fileIo.mkdirSync(importsDir, true);
      }

      const extension: string = this.extractExtension(sourceUri);
      const fileName: string = 'import_' + Date.now().toString() + extension;
      const targetPath: string = importsDir + '/' + fileName;

      const srcFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      const dstFile = fileIo.openSync(
        targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE,
      );
      fileIo.copyFileSync(srcFile.fd, dstFile.fd);
      fileIo.closeSync(srcFile.fd);
      fileIo.closeSync(dstFile.fd);

      return targetPath;
    } catch (_error) {
      return null;
    }
  }

  private getDisplayName(uri: string): string | null {
    if (uri == null || uri.length === 0) {
      return null;
    }
    // Strip query/fragment
    let cleaned: string = uri;
    const queryIdx: number = cleaned.indexOf('?');
    if (queryIdx >= 0) {
      cleaned = cleaned.substring(0, queryIdx);
    }
    const hashIdx: number = cleaned.indexOf('#');
    if (hashIdx >= 0) {
      cleaned = cleaned.substring(0, hashIdx);
    }
    // Last path segment
    const lastSlash: number = cleaned.lastIndexOf('/');
    if (lastSlash >= 0 && lastSlash < cleaned.length - 1) {
      let name: string = cleaned.substring(lastSlash + 1);
      try {
        name = decodeURIComponent(name);
      } catch (_e) {
        // keep as-is
      }
      if (name.length > 0 && name.length <= 80) {
        return name;
      }
    }
    return null;
  }

  private sanitizeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').trim() || 'petnote-backup.json';
  }

  private extractExtension(uri: string): string {
    const lastDot: number = uri.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < uri.length - 1) {
      const ext: string = uri.substring(lastDot);
      if (ext.length <= 6) {
        return ext;
      }
    }
    return '.json';
  }

  private buildErrorResponse(code: string, message: string): Record<string, Object> {
    const response: Record<string, Object> = {};
    response['status'] = 'error';
    response['errorCode'] = code;
    response['errorMessage'] = message;
    return response;
  }

  private describeError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
