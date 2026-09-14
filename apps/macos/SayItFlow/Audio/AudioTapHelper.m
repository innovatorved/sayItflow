#import <AVFoundation/AVFoundation.h>

void SIFRemoveTapSafely(AVAudioNode *node, AVAudioNodeBus bus) {
    if (node == nil) { return; }
    @try {
        [node removeTapOnBus:bus];
    } @catch (__unused NSException *exception) {
        // No tap installed — safe to ignore.
    }
}

BOOL SIFInstallTapSafely(AVAudioNode *node,
                         AVAudioNodeBus bus,
                         AVAudioFrameCount bufferSize,
                         AVAudioFormat *format,
                         void (^block)(AVAudioPCMBuffer *, AVAudioTime *)) {
    if (node == nil) { return NO; }
    @try {
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (__unused NSException *exception) {
        // Hardware format changed out from under us — caller recovers.
        return NO;
    }
}
