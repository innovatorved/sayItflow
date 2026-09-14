#import <AVFoundation/AVFoundation.h>

void SIFRemoveTapSafely(AVAudioNode * _Nonnull node, AVAudioNodeBus bus);

/// Returns NO if AVAudioEngine rejected the tap. `installTapOnBus:` raises an
/// NSException rather than returning an error, and Swift cannot catch those.
BOOL SIFInstallTapSafely(AVAudioNode * _Nonnull node,
                         AVAudioNodeBus bus,
                         AVAudioFrameCount bufferSize,
                         AVAudioFormat * _Nullable format,
                         void (^ _Nonnull block)(AVAudioPCMBuffer * _Nonnull, AVAudioTime * _Nonnull));
