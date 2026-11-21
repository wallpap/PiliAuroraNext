import 'package:pili_aurora_next/app/bootstrap.dart';
import 'package:pili_aurora_next/pages/setting/decoder_test_process.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == decoderTestWorkerArgument) {
    await runDecoderTestWorker();
  } else {
    await bootstrapApplication(arguments);
  }
}
