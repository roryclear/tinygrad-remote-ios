// to be ran with https://github.com/roryclear/tinygrad/tree/new_ios 05ef9db003a681a80e31cfc58f1b61d04e9a537b
#import "tinygrad.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <Metal/Metal.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

static id<MTLDevice> device;
static NSMutableDictionary<NSString *, id> *pipeline_states;
static NSMutableDictionary<NSString *, id> *buffers;
static NSMutableArray<id<MTLCommandBuffer>> *mtl_buffers_in_flight;
static id<MTLCommandQueue> mtl_queue;
static CFSocketRef _socket;
BOOL save_kernels = NO;
NSMutableArray<NSString *> *kernel_keys = nil;
NSMutableDictionary<NSString *, id> *saved_kernels = nil;
NSMutableDictionary<NSString *, id> *kernel_dims = nil;
NSMutableDictionary<NSString *, id> *kernel_times = nil;
NSMutableDictionary<NSString *, id> *buffer_sizes = nil;
NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_sizes = nil;
NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_ints = nil;
static tinygrad *sharedInstance = nil;

@implementation tinygrad


+ (void)start {
    if (!sharedInstance) sharedInstance = [[self alloc] init];
}

+ (void)stop {
    if (_socket) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    sharedInstance = nil;
}
+ (void)toggleSaveKernels { save_kernels = !save_kernels;}

- (instancetype)init {
    self = [super init];
    if (self) {
        pipeline_states = [[NSMutableDictionary alloc] init];
        buffers = [[NSMutableDictionary alloc] init];
        device = MTLCreateSystemDefaultDevice();
        mtl_queue = [device newCommandQueueWithMaxCommandBufferCount:1024];
        mtl_buffers_in_flight = [[NSMutableArray alloc] init];
        kernel_keys = [NSMutableArray array];
        saved_kernels = [[NSMutableDictionary alloc] init];
        kernel_dims = [[NSMutableDictionary alloc] init];
        kernel_times = [[NSMutableDictionary alloc] init];
        buffer_sizes = [[NSMutableDictionary alloc] init];
        kernel_buffer_sizes = [[NSMutableDictionary alloc] init];
        kernel_buffer_ints = [[NSMutableDictionary alloc] init];
        
        _socket = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, AcceptCallback, NULL);
        while (!_socket) { sleep(1); _socket = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, AcceptCallback, NULL); }
        struct sockaddr_in address; memset(&address, 0, sizeof(address)); address.sin_len = sizeof(address); address.sin_port = htons(6667); address.sin_addr.s_addr = INADDR_ANY;
        CFDataRef address_data = CFDataCreate(NULL, (const UInt8 *)&address, sizeof(address));
        while (CFSocketSetAddress(_socket, address_data) != kCFSocketSuccess) sleep(1);
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, _socket, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        NSLog(@"HTTP Server started on port 6667.");
    }
    return self;
}

+ (NSString *)getIP {
    struct ifaddrs *a = 0;
    getifaddrs(&a);
    NSString *ip = nil;
    while (a) {
        if (a->ifa_addr->sa_family == AF_INET &&
            [[NSString stringWithUTF8String:a->ifa_name] isEqualToString:@"en0"]) {
            ip = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)a->ifa_addr)->sin_addr)];
            break;
        }
        a = a->ifa_next;
    }
    return ip ? [NSString stringWithFormat:@"tinygrad: %@:6667", ip] : @"Waiting for WiFi...";
}

static void sendHTTPResponse(CFSocketNativeHandle handle, const void *data, size_t dataSize) {
    char response_header[256];
    snprintf(response_header, sizeof(response_header),
             "HTTP/1.1 200 OK\r\n"
             "Content-Type: text/plain\r\n"
             "Content-Length: %zu\r\n"
             "Connection: close\r\n\r\n", dataSize);
    send(handle, response_header, strlen(response_header), 0);
    send(handle, data, dataSize, 0);
    close(handle);
}

static NSMutableDictionary<NSString *, id> *extractValues(NSString *x) {
    NSMutableDictionary<NSString *, id> *values = [@{@"op": [x componentsSeparatedByString:@"("][0]} mutableCopy];
    NSDictionary<NSString *, NSString *> *patterns = @{@"name": @"name='([^']+)'",@"datahash": @"datahash='([^']+)'",@"global_sizes": @"global_size=\\(([^)]+)\\)",
        @"local_sizes": @"local_size=\\(([^)]+)\\)",@"wait": @"wait=(True|False)",@"bufs": @"bufs=\\(([^)]+)\\)",@"vals": @"vals=\\(([^)]+)\\)",
        @"buffer_num": @"buffer_num=(\\d+)",@"size": @"size=(\\d+)"}; // Changed size pattern to capture only the number
    [patterns enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *pattern, BOOL *stop) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:x options:0 range:NSMakeRange(0, x.length)];
        if (match) {
            NSString *contents = [x substringWithRange:[match rangeAtIndex:1]];
            NSMutableArray<NSString *> *extracted_values = [NSMutableArray array];
            for (NSString *value in [contents componentsSeparatedByString:@","]) {
                NSString *trimmed_value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed_value.length > 0) {
                    [extracted_values addObject:trimmed_value];
                }
            }
            values[key] = [extracted_values copy];
        }
    }];
    return values;
}

static void AcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data_in, void *info) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data_in;
    struct timeval timeout;
    timeout.tv_sec = 10;
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));
    char buffer[1024 * 500];
    memset(buffer, 0, sizeof(buffer));
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    NSInteger header_idx = -1;
    NSInteger size = 0;
    while (1) {
        ssize_t bytes_in = recv(handle, buffer, sizeof(buffer) - 1, 0);
        if (bytes_in <= 0) break;
        buffer[bytes_in] = '\0';
        CFDataAppendBytes(data, (UInt8 *)buffer, bytes_in);
        if (header_idx == -1) {
            NSData *needle = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
            const UInt8 *bytes = CFDataGetBytePtr(data);
            CFIndex len = CFDataGetLength(data);
            for (CFIndex i = 0; i <= len - (CFIndex)needle.length; i++) {
                if (memcmp(bytes + i, needle.bytes, needle.length) == 0) {
                    header_idx = i + (NSInteger)needle.length;
                    break;
                }
            }
            if (header_idx != -1) {
                NSData *headerData = [NSData dataWithBytes:bytes length:header_idx];
                NSString *headerStr = [[NSString alloc] initWithData:headerData
                                                        encoding:NSUTF8StringEncoding];
                for (NSString *line in [headerStr componentsSeparatedByString:@"\r\n"]) {
                    if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                        NSString *value = [[line componentsSeparatedByString:@":"] lastObject];
                        size = [value stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]].integerValue;
                        break;
                    }
                }
            }
        }
        if (header_idx != -1 && CFDataGetLength(data) >= size + header_idx) break;
    }

    shutdown(handle, SHUT_RD);
    NSData *all = (__bridge NSData *)data;
    if (header_idx == -1 || (NSUInteger)header_idx > all.length) {
        CFRelease(data);
        close(handle);
        return;
    }

    const uint8_t *p   = (const uint8_t *)all.bytes + header_idx;
    NSUInteger     rem = all.length - header_idx;
    uint32_t meta_len  = 0; memcpy(&meta_len, p, 4); p += 4; rem -= 4;

    NSData *meta = [NSData dataWithBytes:p length:meta_len]; p += meta_len; rem -= meta_len;
    const uint8_t *blobs = p;

    NSArray *list = [NSJSONSerialization JSONObjectWithData:meta options:0 error:nil];
    for (NSDictionary *item in list) {
        NSString *key = item.allKeys.firstObject;
        if ([key isEqualToString:@"buff_alloc"]) {
            [buffers setObject:[device newBufferWithLength:[item[key][@"size"] intValue] options:MTLResourceStorageModeShared] forKey:item[key][@"num"]];
            if (save_kernels) [buffer_sizes setObject:@([item[key][@"size"] intValue]) forKey:item[key][@"num"]];
        } else if ([key isEqualToString:@"copyin"]) {
            for(int i = 0; i < mtl_buffers_in_flight.count; i++){ [mtl_buffers_in_flight[i] waitUntilCompleted]; }
            [mtl_buffers_in_flight removeAllObjects];
            id<MTLBuffer> b = buffers[item[key][@"dest"]];
            memcpy(b.contents, blobs + [item[key][@"off"] unsignedLongLongValue], [item[key][@"len"] unsignedLongLongValue]);
        } else if ([key isEqualToString:@"program"]) {
            NSString *base64 = item[key][@"lib"];
            NSString *src = item[key][@"src"];
            NSString *name = item[key][@"name"];
            NSData *libraryData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
            dispatch_data_t dispatchData =
                dispatch_data_create(
                    libraryData.bytes,
                    libraryData.length,
                    dispatch_get_main_queue(),
                    DISPATCH_DATA_DESTRUCTOR_DEFAULT
                );
            NSError *error = nil;
            id<MTLLibrary> library = [device newLibraryWithData:dispatchData error:&error];
            id<MTLFunction> function = [library newFunctionWithName:name];
            id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
            pipeline_states[name] = pipeline;
            
            if(save_kernels){
                [kernel_keys addObject: name];
                [saved_kernels setObject:src forKey:name];
                [kernel_buffer_sizes setObject:[[NSMutableArray alloc] init] forKey:name];
                [kernel_buffer_ints setObject:[[NSMutableArray alloc] init] forKey:name];
            }
        } else if ([key isEqualToString:@"call"]) {
            NSString *name = item[key][@"name"];
            NSArray *kernel_buffers = item[key][@"buffers"];
            NSArray *buffer_offsets = item[key][@"buffer_offsets"];
            NSArray *vals = item[key][@"vals"];
            NSArray *local_sizes = item[key][@"local_size"];
            NSArray *global_sizes = item[key][@"global_size"];
            BOOL wait = [item[key][@"wait"] boolValue];
            NSInteger max_size = [pipeline_states[name] maxTotalThreadsPerThreadgroup];
            if(max_size < [local_sizes[0] intValue]*[local_sizes[1] intValue]*[local_sizes[2] intValue]) {
                sendHTTPResponse(handle, "inf", 3);
                return;
            }
            id<MTLCommandBuffer> command_buffer = [mtl_queue commandBuffer];
            id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
            [encoder setComputePipelineState:pipeline_states[name]];
            for(int i = 0; i < [kernel_buffers count]; i++){
                if(save_kernels && kernel_buffer_sizes[name].count == i) [kernel_buffer_sizes[name] addObject:buffer_sizes[kernel_buffers[i]]];
                [encoder setBuffer:buffers[kernel_buffers[i]] offset:[buffer_offsets[i] intValue] atIndex:i];
            }
            for (NSUInteger i = 0; i < [vals count]; i++) {
                if(save_kernels && kernel_buffer_ints[name].count == i) [kernel_buffer_ints[name] addObject:@([vals[i] integerValue])];
                int32_t value = (int32_t)[vals[i] integerValue];
                [encoder setBytes:&value length:sizeof(int32_t) atIndex:(NSInteger)i + (NSInteger)[kernel_buffers count]];
            }
            MTLSize global_size = MTLSizeMake([global_sizes[0] intValue], [global_sizes[1] intValue], [global_sizes[2] intValue]);
            MTLSize local_size = MTLSizeMake([local_sizes[0] intValue], [local_sizes[1] intValue], [local_sizes[2] intValue]);
            [encoder dispatchThreadgroups:global_size threadsPerThreadgroup:local_size];
            [encoder endEncoding];
            [command_buffer commit];
            if (wait || save_kernels) {
                [command_buffer waitUntilCompleted];
                float time = (float)(command_buffer.GPUEndTime - command_buffer.GPUStartTime);
                [kernel_times setObject:@((command_buffer.GPUEndTime - command_buffer.GPUStartTime) * 1e9) forKey:name]; //ns
                if (wait) {
                    const char *time_string = (time == 0) ? "inf" : [[NSString stringWithFormat:@"%e", time] UTF8String];
                    if (strcmp(time_string, "inf") == 0) mtl_queue = [device newCommandQueueWithMaxCommandBufferCount:1024];
                    sendHTTPResponse(handle, time_string, strlen(time_string));
                    return;
                }
            }
            [mtl_buffers_in_flight addObject: command_buffer];
        } else if ([key isEqualToString:@"copyout"]) {
            for(int i = 0; i < mtl_buffers_in_flight.count; i++){ [mtl_buffers_in_flight[i] waitUntilCompleted]; }
            [mtl_buffers_in_flight removeAllObjects];
            id<MTLBuffer> buffer = buffers[item[key]];
            sendHTTPResponse(handle, buffer.contents, buffer.length);
            return;
        }
    }
    CFRelease(data);
    const char *response = "HTTP/1.1 200 OK\r\n"
                           "Content-Type: text/plain\r\n"
                           "Content-Length: 2\r\n"
                           "\r\n"
                           "OK";
    send(handle, response, strlen(response), 0);
    close(handle);
}

@end
