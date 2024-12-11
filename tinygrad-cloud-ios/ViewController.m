#import "ViewController.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface ViewController ()
@property (nonatomic) CFSocketRef socket;
@end

@implementation ViewController

id<MTLDevice> device;
NSMutableDictionary<NSString *, id> *objects;
NSMutableDictionary<NSString *, id> *buffers;
NSMutableArray<id<MTLCommandBuffer>> *mtl_buffers_in_flight;
id<MTLCommandQueue> mtl_queue;

- (void)viewDidLoad {
    objects = [[NSMutableDictionary alloc] init];
    buffers = [[NSMutableDictionary alloc] init];
    device = MTLCreateSystemDefaultDevice();
    mtl_queue = [device newCommandQueueWithMaxCommandBufferCount:1024];
    mtl_buffers_in_flight = [[NSMutableArray alloc] init];
    [super viewDidLoad];
    self.socket = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, AcceptCallback, NULL);
    while (!self.socket) {
        sleep(1);
        self.socket = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, AcceptCallback, NULL);
    }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_port = htons(6667);  // use same port on tinygrad
    address.sin_addr.s_addr = INADDR_ANY;
    CFDataRef addressData = CFDataCreate(NULL, (const UInt8 *)&address, sizeof(address));
    while (CFSocketSetAddress(self.socket, addressData) != kCFSocketSuccess) {
        sleep(1);
    }
    CFRelease(addressData);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, self.socket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    NSLog(@"HTTP Server started on port 6667.");
}

NSArray<NSString *> *extractValues(NSString *pattern, NSString *x) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSRange range = [[regex firstMatchInString:x options:0 range:NSMakeRange(0, x.length)] rangeAtIndex:1];
    NSString *contents = [x substringWithRange:range];
    NSArray<NSString *> *rawValues = [contents componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSString *value in rawValues) {
        NSString *trimmedValue = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedValue.length > 0) {
            [values addObject:trimmedValue];
        }
    }
    return [values copy];
}

static void AcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data;
    char buffer[1024 * 500] = {0};
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));
    ssize_t bytes = recv(handle, buffer, sizeof(buffer) - 1, 0);
    buffer[bytes] = '\0';
    CFDataRef dataRef = CFDataCreate(NULL, (UInt8 *)buffer, (CFIndex)bytes);
    CFHTTPMessageRef httpRequest = CFHTTPMessageCreateEmpty(NULL, TRUE);
    CFHTTPMessageAppendBytes(httpRequest, CFDataGetBytePtr(dataRef), CFDataGetLength(dataRef));
    NSString *requestPath = [(__bridge_transfer NSURL *)CFHTTPMessageCopyRequestURL(httpRequest) path];
    if ([requestPath hasPrefix:@"/renderer"]) {
        char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n[\"tinygrad.renderer.cstyle\", \"MetalRenderer\", []]";
        send(handle, response, strlen(response), 0);
        close(handle);
        return;
    } else if ([requestPath hasPrefix:@"/batch"]) {
        CFStringRef contentLengthHeader = CFHTTPMessageCopyHeaderFieldValue(httpRequest, CFSTR("Content-Length"));
        NSInteger size = CFStringGetIntValue(contentLengthHeader); CFRelease(contentLengthHeader);
        CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
        while (bytes > 0 || CFDataGetLength(data) < size) {
            if(bytes > 0) {
                CFDataAppendBytes(data, (UInt8 *)buffer, bytes);
            }
            bytes = recv(handle, buffer, sizeof(buffer) - 1, 0);
        }
        CFDataReplaceBytes(data, CFRangeMake(0, CFDataGetLength(data) - size), NULL, 0);
        
        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex length = CFDataGetLength(data);
        NSData *rangeData;
        NSMutableDictionary *_h = [[NSMutableDictionary alloc] init];
        NSInteger ptr = 0;
        NSString *stringData;
        NSMutableString *datahash = [NSMutableString stringWithCapacity:0x40];
        while (ptr < length) {
            NSData *slicedData = [NSData dataWithBytes:bytes + ptr + 0x20 length:0x28 - 0x20];
            uint64_t datalen = 0;
            [slicedData getBytes:&datalen length:sizeof(datalen)];
            datalen = CFSwapInt64LittleToHost(datalen);
            const UInt8 *datahash_bytes = bytes + ptr;
            datahash = [NSMutableString stringWithCapacity:0x40];
            for (int i = 0; i < 0x20; i++) {
                [datahash appendFormat:@"%02x", datahash_bytes[i]];
            }
            rangeData = [NSData dataWithBytes:bytes + (ptr + 0x28) length:datalen];
            _h[datahash] = rangeData;
            ptr += 0x28 + datalen;
        }
        CFRelease(data);
        stringData = [[NSString alloc] initWithData:rangeData encoding:NSUTF8StringEncoding];
        NSMutableArray *_q = [NSMutableArray array];
        NSArray *ops = @[@"BufferAlloc", @"BufferFree", @"CopyIn", @"CopyOut", @"ProgramAlloc", @"ProgramFree", @"ProgramExec"];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(%@)\\(", [ops componentsJoinedByString:@"|"]] options:0 error:nil];
        __block NSInteger lastIndex = 0;
        [regex enumerateMatchesInString:stringData options:0 range:NSMakeRange(0, stringData.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            NSRange range = NSMakeRange(lastIndex, match.range.location - lastIndex);
            [_q addObject:[[stringData substringWithRange:range] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]]];
            lastIndex = match.range.location;
        }];
        [_q addObject:[[stringData substringFromIndex:lastIndex] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]]];

        for (NSString *x in _q) {
            if ([x hasPrefix:@"BufferAlloc"]) {
                NSLog(@"BufferAlloc");
                NSString *buffer_num = extractValues(@"buffer_num=(\\d+)", x)[0];
                NSString *size = extractValues(@"size=(\\d+)", x)[0];
                [buffers setObject:[device newBufferWithLength:[size intValue] options:MTLResourceStorageModeShared] forKey:buffer_num];
            } else if ([x hasPrefix:@"BufferFree"]) {
                NSLog(@"BufferFree");
                NSString *buffer_num = extractValues(@"buffer_num=(\\d+)", x)[0];
                [buffers removeObjectForKey: buffer_num];
            } else if ([x hasPrefix:@"CopyIn"]) {
                NSLog(@"CopyIn %@",x);
                NSString *buffer_num = extractValues(@"buffer_num=(\\d+)", x)[0];
                NSString *datahash = extractValues(@"datahash='([^']+)'", x)[0];
                id<MTLBuffer> buffer = buffers[buffer_num];
                NSData *data = _h[datahash];
                memcpy(buffer.contents, data.bytes, data.length);
            } else if ([x hasPrefix:@"CopyOut"]) {
                NSLog(@"copyout %@",x);
                for(int i = 0; i < mtl_buffers_in_flight.count; i++){
                    [mtl_buffers_in_flight[i] waitUntilCompleted];
                }
                [mtl_buffers_in_flight removeAllObjects];
                NSString *buffer_num = extractValues(@"buffer_num=(\\d+)", x)[0];
                id<MTLBuffer> buffer = buffers[buffer_num];
                const void *rawData = buffer.contents;
                size_t bufferSize = buffer.length;
                char responseHeader[256];
                snprintf(responseHeader, sizeof(responseHeader),
                         "HTTP/1.1 200 OK\r\n"
                         "Content-Type: text/plain\r\n"
                         "Content-Length: %zu\r\n"
                         "Connection: close\r\n\r\n", bufferSize);
                send(handle, responseHeader, strlen(responseHeader), 0);
                send(handle, rawData, bufferSize, 0);
                return;
            } else if ([x hasPrefix:@"ProgramAlloc"]) {
                NSLog(@"ProgramAlloc");
                NSString *name = extractValues(@"name='([^']+)'", x)[0];
                NSString *datahash = extractValues(@"datahash='([^']+)'", x)[0];
                NSString *prg = [[NSString alloc] initWithData:_h[datahash] encoding:NSUTF8StringEncoding];
                NSError *error = nil;
                id<MTLLibrary> library = [device newLibraryWithSource:prg
                                                               options:nil
                                                                 error:&error];
                MTLComputePipelineDescriptor *descriptor = [[MTLComputePipelineDescriptor alloc] init];
                descriptor.computeFunction = [library newFunctionWithName:name];;
                descriptor.supportIndirectCommandBuffers = YES;
                MTLComputePipelineReflection *reflection = nil;
                id<MTLComputePipelineState> pipeline_state = [device newComputePipelineStateWithDescriptor:descriptor
                                                                                                   options:MTLPipelineOptionNone
                                                                                                reflection:&reflection
                                                                                                     error:&error];
                [objects setObject:pipeline_state forKey:@[name,datahash]];
                [_h removeObjectForKey:datahash];
            } else if ([x hasPrefix:@"ProgramFree"]) {
                NSLog(@"ProgramFree");
            } else if ([x hasPrefix:@"ProgramExec"]) {
                NSLog(@"ProgramExec %@",x);
                NSString *name = extractValues(@"name='([^']+)'", x)[0];
                NSString *datahash = extractValues(@"datahash='([^']+)'", x)[0];
                NSArray<NSString *> *gloal_sizes = extractValues(@"global_size=\\(([^)]+)\\)", x);
                NSArray<NSString *> *local_sizes = extractValues(@"local_size=\\(([^)]+)\\)", x);
                BOOL wait = [extractValues(@"wait=(True|False)", x)[0] isEqualToString:@"True"];
                NSArray<NSString *> *bufs = extractValues(@"bufs=\\(([^)]+)\\)", x);
                NSArray<NSString *> *vals = extractValues(@"vals=\\(([^)]+)\\)", x);
                                
                id<MTLCommandBuffer> commandBuffer = [mtl_queue commandBuffer];
                id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
                [computeEncoder setComputePipelineState:objects[@[name,datahash]]];
                for(int i = 0; i < bufs.count; i++){
                    [computeEncoder setBuffer:buffers[bufs[i]] offset:0 atIndex:i];
                }
                for (int i = 0; i < vals.count; i++) {
                    NSInteger value = [vals[i] integerValue];
                    [computeEncoder setBytes:&value length:sizeof(NSInteger) atIndex:i + bufs.count];
                }
                MTLSize gridSize = MTLSizeMake([gloal_sizes[0] intValue], [gloal_sizes[1] intValue], [gloal_sizes[2] intValue]);
                MTLSize threadGroupSize = MTLSizeMake([local_sizes[0] intValue], [local_sizes[1] intValue], [local_sizes[2] intValue]);
                [computeEncoder dispatchThreadgroups:gridSize threadsPerThreadgroup:threadGroupSize];
                [computeEncoder endEncoding];
                [commandBuffer commit];
                if(wait) {
                    [commandBuffer waitUntilCompleted];
                    float time = (float)(commandBuffer.GPUEndTime - commandBuffer.GPUStartTime);
                    NSString *timeString = [NSString stringWithFormat:@"%e", time];
                    const char *timeCString = [timeString UTF8String];
                    size_t timeCStringLength = strlen(timeCString);
                    char header[256];
                    snprintf(header, sizeof(header),
                             "HTTP/1.1 200 OK\r\n"
                             "Content-Type: text/plain\r\n"
                             "Content-Length: %zu\r\n"
                             "Connection: close\r\n\r\n", timeCStringLength);
                    send(handle, header, strlen(header), 0);
                    send(handle, timeCString, timeCStringLength, 0);
                    return;
                }
                [mtl_buffers_in_flight addObject: commandBuffer];
            }
        }
        return;
    }
}
@end
