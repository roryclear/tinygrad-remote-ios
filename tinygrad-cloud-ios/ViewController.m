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
NSMutableDictionary<NSString *, id> *pipeline_states;
NSMutableDictionary<NSString *, id> *buffers;
NSMutableArray<id<MTLCommandBuffer>> *mtl_buffers_in_flight;
id<MTLCommandQueue> mtl_queue;

- (void)viewDidLoad {
    pipeline_states = [[NSMutableDictionary alloc] init];
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
    CFDataRef address_data = CFDataCreate(NULL, (const UInt8 *)&address, sizeof(address));
    while (CFSocketSetAddress(self.socket, address_data) != kCFSocketSuccess) sleep(1);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, self.socket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    NSLog(@"HTTP Server started on port 6667.");
}

static void AcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data;
    char buffer[1024 * 500] = {0};
    struct timeval timeout;
    timeout.tv_sec = 10;
    timeout.tv_usec = 0;
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));
    ssize_t bytes = recv(handle, buffer, sizeof(buffer) - 1, 0);
    buffer[bytes] = '\0';
    CFDataRef data_ref = CFDataCreate(NULL, (UInt8 *)buffer, (CFIndex)bytes);
    CFHTTPMessageRef http_request = CFHTTPMessageCreateEmpty(NULL, TRUE);
    CFHTTPMessageAppendBytes(http_request, CFDataGetBytePtr(data_ref), CFDataGetLength(data_ref));
    NSString *request_path = [(__bridge_transfer NSURL *)CFHTTPMessageCopyRequestURL(http_request) path];
    if ([request_path hasPrefix:@"/renderer"]) {
        char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n[\"tinygrad.renderer.cstyle\", \"MetalRenderer\", []]";
        send(handle, response, strlen(response), 0);
        close(handle);
    } else if ([request_path hasPrefix:@"/batch"]) {
        CFStringRef content_length = CFHTTPMessageCopyHeaderFieldValue(http_request, CFSTR("Content-Length"));
        NSInteger size = CFStringGetIntValue(content_length);
        CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
        NSInteger header_idx = -1;
        while (1) {
            CFDataAppendBytes(data, (UInt8 *)buffer, bytes);
            if (header_idx == -1) {
                CFDataRef h_data = CFStringCreateExternalRepresentation(NULL, CFSTR("\r\n\r\n"), kCFStringEncodingASCII, 0);
                for (CFIndex i = 0; i <= CFDataGetLength(data) - CFDataGetLength(h_data); i++) {
                    if (memcmp(CFDataGetBytePtr(data) + i, CFDataGetBytePtr(h_data), CFDataGetLength(h_data)) == 0) {
                        header_idx = i + CFDataGetLength(h_data);
                        break;
                    }
                }
            }
            if(CFDataGetLength(data) + header_idx >= size) break;
            bytes = recv(handle, buffer, sizeof(buffer) - 1, 0);
        }
        shutdown(handle, SHUT_RD);

        CFDataReplaceBytes(data, CFRangeMake(0, CFDataGetLength(data) - size), NULL, 0);
        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex length = CFDataGetLength(data);
        NSData *rangeData;
        NSMutableDictionary *_h = [[NSMutableDictionary alloc] init];
        NSInteger ptr = 0;
        NSString *string_data;
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
        string_data = [[NSString alloc] initWithData:rangeData encoding:NSUTF8StringEncoding];
        NSMutableArray *_q = [NSMutableArray array];
        NSArray *ops = @[@"BufferAlloc", @"BufferFree", @"CopyIn", @"CopyOut", @"ProgramAlloc", @"ProgramFree", @"ProgramExec"];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(%@)\\(", [ops componentsJoinedByString:@"|"]] options:0 error:nil];
        __block NSInteger lastIndex = 0;
        [regex enumerateMatchesInString:string_data options:0 range:NSMakeRange(0, string_data.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            NSRange range = NSMakeRange(lastIndex, match.range.location - lastIndex);
            [_q addObject:[[string_data substringWithRange:range] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]]];
            lastIndex = match.range.location;
        }];
        [_q addObject:[[string_data substringFromIndex:lastIndex] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]]];

        for (NSString *x in _q) {
            NSDictionary<NSString *, NSString *> *patterns = @{@"name": @"name='([^']+)'",@"datahash": @"datahash='([^']+)'",@"global_sizes": @"global_size=\\(([^)]+)\\)",
                @"local_sizes": @"local_size=\\(([^)]+)\\)",@"wait": @"wait=(True|False)",@"bufs": @"bufs=\\(([^)]+)\\)",@"vals": @"vals=\\(([^)]+)\\)",
                @"buffer_num": @"buffer_num=(\\d+)",@"size": @"size=(\\d+)"};
            NSMutableDictionary<NSString *, NSArray<NSString *> *> *values = [NSMutableDictionary dictionary];
            [patterns enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *pattern, BOOL *stop) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
                NSRange range = [[regex firstMatchInString:x options:0 range:NSMakeRange(0, x.length)] rangeAtIndex:1];
                NSString *contents = [x substringWithRange:range];
                NSArray<NSString *> *rawValues = [contents componentsSeparatedByString:@","];
                NSMutableArray<NSString *> *extracted_values = [NSMutableArray array];
                for (NSString *value in rawValues) {
                    NSString *trimmed_value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmed_value.length > 0) {
                        [extracted_values addObject:trimmed_value];
                    }
                }
                values[key] = [extracted_values copy];
            }];

            if ([x hasPrefix:@"BufferAlloc"]) {
                [buffers setObject:[device newBufferWithLength:[values[@"size"][0] intValue] options:MTLResourceStorageModeShared] forKey:values[@"buffer_num"][0]];
            } else if ([x hasPrefix:@"BufferFree"]) {
                [buffers removeObjectForKey: values[@"buffer_num"][0]];
            } else if ([x hasPrefix:@"CopyIn"]) {
                id<MTLBuffer> buffer = buffers[values[@"buffer_num"][0]];
                NSData *data = _h[values[@"datahash"][0]];
                memcpy(buffer.contents, data.bytes, data.length);
            } else if ([x hasPrefix:@"CopyOut"]) {
                for(int i = 0; i < mtl_buffers_in_flight.count; i++){
                    [mtl_buffers_in_flight[i] waitUntilCompleted];
                }
                [mtl_buffers_in_flight removeAllObjects];
                id<MTLBuffer> buffer = buffers[values[@"buffer_num"][0]];
                const void *rawData = buffer.contents;
                size_t bufferSize = buffer.length;
                char response_header[256];
                snprintf(response_header, sizeof(response_header),
                         "HTTP/1.1 200 OK\r\n"
                         "Content-Type: text/plain\r\n"
                         "Content-Length: %zu\r\n"
                         "Connection: close\r\n\r\n", bufferSize);
                send(handle, response_header, strlen(response_header), 0);
                send(handle, rawData, bufferSize, 0);
            } else if ([x hasPrefix:@"ProgramAlloc"]) {
                if ([pipeline_states objectForKey:@[values[@"name"][0],values[@"datahash"][0]]]) continue;
                NSString *prg = [[NSString alloc] initWithData:_h[values[@"datahash"][0]] encoding:NSUTF8StringEncoding];
                NSError *error = nil;
                id<MTLLibrary> library = [device newLibraryWithSource:prg
                                                              options:nil
                                                                error:&error];
                MTLComputePipelineDescriptor *descriptor = [[MTLComputePipelineDescriptor alloc] init];
                descriptor.computeFunction = [library newFunctionWithName:values[@"name"][0]];;
                descriptor.supportIndirectCommandBuffers = YES;
                MTLComputePipelineReflection *reflection = nil;
                id<MTLComputePipelineState> pipeline_state = [device newComputePipelineStateWithDescriptor:descriptor
                                                                                                   options:MTLPipelineOptionNone
                                                                                                reflection:&reflection
                                                                                                     error:&error];
                [pipeline_states setObject:pipeline_state forKey:@[values[@"name"][0],values[@"datahash"][0]]];
            } else if ([x hasPrefix:@"ProgramFree"]) {
                [pipeline_states removeObjectForKey:@[values[@"name"][0],values[@"datahash"][0]]];
            } else if ([x hasPrefix:@"ProgramExec"]) {
                id<MTLCommandBuffer> commandBuffer = [mtl_queue commandBuffer];
                id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
                [encoder setComputePipelineState:pipeline_states[@[values[@"name"][0],values[@"datahash"][0]]]];
                for(int i = 0; i < values[@"bufs"].count; i++){
                    [encoder setBuffer:buffers[values[@"bufs"][i]] offset:0 atIndex:i];
                }
                for (int i = 0; i < values[@"vals"].count; i++) {
                    NSInteger value = [values[@"vals"][i] integerValue];
                    [encoder setBytes:&value length:sizeof(NSInteger) atIndex:i + values[@"bufs"].count];
                }
                MTLSize global_size = MTLSizeMake([values[@"global_sizes"][0] intValue], [values[@"global_sizes"][1] intValue], [values[@"global_sizes"][2] intValue]);
                MTLSize local_size = MTLSizeMake([values[@"local_sizes"][0] intValue], [values[@"local_sizes"][1] intValue], [values[@"local_sizes"][2] intValue]);
                [encoder dispatchThreadgroups:global_size threadsPerThreadgroup:local_size];
                [encoder endEncoding];
                [commandBuffer commit];
                if([values[@"wait"][0] isEqualToString:@"True"]) {
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
                }
                [mtl_buffers_in_flight addObject: commandBuffer];
            }
        }
    }
}
@end
