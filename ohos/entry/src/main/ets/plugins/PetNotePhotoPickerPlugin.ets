import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'PetNotePhotoPickerPlugin';
const CHANNEL_NAME = 'petnote/native_pet_photo_picker';
const MAX_BATCH_SELECT = 20;

export default class PetNotePhotoPickerPlugin implements FlutterPlugin, MethodCallHandler {
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
      case 'pickPetPhoto':
        this.handlePickSinglePhoto(result);
        break;
      case 'pickPetPhotos':
        this.handlePickMultiplePhotos(result);
        break;
      case 'deletePetPhoto':
        this.handleDeletePhoto(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async handlePickSinglePhoto(result: MethodResult): Promise<void> {
    try {
      const uris = await this.pickPhotosFromGallery(1);
      if (uris == null || uris.length === 0) {
        result.success(this.buildResponse('cancelled'));
        return;
      }
      const localPath = await this.copyUriToSandbox(uris[0]);
      if (localPath == null) {
        result.success(this.buildErrorResponse(
          'platformError',
          '无法将所选照片复制到应用存储。'
        ));
        return;
      }
      const response = this.buildResponse('success');
      response['localPath'] = localPath;
      result.success(response);
    } catch (error) {
      result.success(this.buildErrorResponse(
        'platformError',
        this.describeError(error)
      ));
    }
  }

  private async handlePickMultiplePhotos(result: MethodResult): Promise<void> {
    try {
      const uris = await this.pickPhotosFromGallery(MAX_BATCH_SELECT);
      if (uris == null || uris.length === 0) {
        result.success(this.buildResponse('cancelled'));
        return;
      }
      const localPaths: Array<string> = [];
      for (let i = 0; i < uris.length; i++) {
        const localPath = await this.copyUriToSandbox(uris[i]);
        if (localPath != null) {
          localPaths.push(localPath);
        }
      }
      if (localPaths.length === 0) {
        result.success(this.buildErrorResponse(
          'platformError',
          '无法将任何所选照片复制到应用存储。'
        ));
        return;
      }
      const response = this.buildResponse('success');
      response['localPaths'] = localPaths;
      result.success(response);
    } catch (error) {
      result.success(this.buildErrorResponse(
        'platformError',
        this.describeError(error)
      ));
    }
  }

  private handleDeletePhoto(call: MethodCall, result: MethodResult): void {
    try {
      const pathVal: Object | null = call.argument('path');
      const path: string | null = typeof pathVal === 'string' ? pathVal : null;

      if (path == null || path.length === 0) {
        result.success(null);
        return;
      }

      const context = this.pluginBinding?.getApplicationContext();
      if (context == null) {
        result.success(null);
        return;
      }

      // Safety: only delete files within app sandbox directories
      const allowedPrefixes: Array<string> = [
        context.filesDir,
        context.cacheDir,
        context.tempDir,
      ];
      const isAllowed = allowedPrefixes.some(
        (prefix: string) => path!.startsWith(prefix)
      );
      if (!isAllowed) {
        result.success(null);
        return;
      }

      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      result.success(null);
    } catch (_error) {
      result.success(null);
    }
  }

  private async pickPhotosFromGallery(
    maxCount: number
  ): Promise<Array<string> | null> {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.maxSelectNumber = maxCount;
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    const selectResult = await picker.select(options);
    if (selectResult == null || selectResult.photoUris == null) {
      return null;
    }
    const uris: Array<string> = [];
    for (let i = 0; i < selectResult.photoUris.length; i++) {
      const uri = selectResult.photoUris[i];
      if (typeof uri === 'string' && uri.length > 0) {
        uris.push(uri);
      }
    }
    return uris.length > 0 ? uris : null;
  }

  private async copyUriToSandbox(sourceUri: string): Promise<string | null> {
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      return null;
    }
    try {
      const extension = this.extractExtension(sourceUri);
      const filename = util.generateRandomUUID() + extension;
      const dirPath = context.filesDir + '/pet_photos';
      const targetPath = dirPath + '/' + filename;

      // Ensure directory exists
      if (!fileIo.accessSync(dirPath)) {
        fileIo.mkdirSync(dirPath, true);
      }

      // Copy file via file descriptors
      const sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      const targetFile = fileIo.openSync(
        targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE
      );
      fileIo.copyFileSync(sourceFile.fd, targetFile.fd);
      fileIo.closeSync(sourceFile.fd);
      fileIo.closeSync(targetFile.fd);

      return targetPath;
    } catch (error) {
      return null;
    }
  }

  private extractExtension(uri: string): string {
    const lastDot = uri.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < uri.length - 1) {
      const ext = uri.substring(lastDot);
      if (ext.length <= 5) {
        return ext;
      }
    }
    return '.jpg';
  }

  private buildResponse(status: string): Record<string, Object> {
    const response: Record<string, Object> = {};
    response['status'] = status;
    return response;
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
