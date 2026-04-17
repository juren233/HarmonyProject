import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/logging/app_crash_diagnostics.dart';
import 'package:petnote/logging/app_log_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppCrashDiagnosticsBinding.instance.resetForTesting();
  });

  tearDown(() {
    AppCrashDiagnosticsBinding.instance.resetForTesting();
  });

  test('records unhandled Flutter errors through the global handler', () {
    final controller = AppLogController.memory();
    final binding = AppCrashDiagnosticsBinding.instance;

    binding.installGlobalHandlers();
    binding.attachController(controller);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('flutter boom'),
        stack: StackTrace.current,
        library: 'widgets',
      ),
    );

    expect(controller.crashDiagnosticEntries, hasLength(1));
    expect(controller.crashDiagnosticEntries.single.title, '捕获未处理 Flutter 异常');
    expect(
      controller.crashDiagnosticEntries.single.message,
      contains('flutter boom'),
    );
  });

  test('buffers early zone errors until a controller attaches', () {
    final binding = AppCrashDiagnosticsBinding.instance;

    binding.installGlobalHandlers();
    binding.recordZoneError(
      StateError('zone boom'),
      StackTrace.current,
    );

    final controller = AppLogController.memory();
    binding.attachController(controller);

    expect(controller.crashDiagnosticEntries, hasLength(1));
    expect(controller.crashDiagnosticEntries.single.title, '捕获未处理 Dart 异常');
    expect(
      controller.crashDiagnosticEntries.single.details,
      contains('source=zone'),
    );
  });

  test('records platform dispatcher errors and reports them handled', () {
    final controller = AppLogController.memory();
    final binding = AppCrashDiagnosticsBinding.instance;

    binding.installGlobalHandlers();
    binding.attachController(controller);

    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('platform boom'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    expect(controller.crashDiagnosticEntries, hasLength(1));
    expect(controller.crashDiagnosticEntries.single.title, '捕获未处理 Dart 异常');
    expect(
      controller.crashDiagnosticEntries.single.details,
      contains('source=platform_dispatcher'),
    );
  });
}
