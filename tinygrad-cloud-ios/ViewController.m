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

- (void)viewDidLoad {
    objects = [[NSMutableDictionary alloc] init];
    device = MTLCreateSystemDefaultDevice();
    //[objects setObject: device forKey:@"d"];
    [super viewDidLoad];
    [self startHTTPServer];
}


- (void)startHTTPServer {
    self.socket = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, AcceptCallback, NULL);
    if (!self.socket) {
        NSLog(@"Unable to create socket.");
        return;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(6667);  //use same port on tinygrad
    address.sin_addr.s_addr = INADDR_ANY;
    
    CFDataRef addressData = CFDataCreate(NULL, (const UInt8 *)&address, sizeof(address));
    if (CFSocketSetAddress(self.socket, addressData) != kCFSocketSuccess) {
        NSLog(@"Failed to bind socket to address.");
        CFRelease(self.socket);
        self.socket = NULL;
        exit(0); //TODO, add ui or retry
        return;
    }
    CFRelease(addressData);
    
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, self.socket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    
    NSLog(@"HTTP Server started on port 6667.");
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
        
        //tinygrad decentralise???
        NSData *rangeData;
        NSMutableDictionary *_h = [[NSMutableDictionary alloc] init];
        NSMutableString *datahash;
        NSInteger ptr = 0;
        while(ptr < length){
            NSData *slicedData = [NSData dataWithBytes:bytes + ptr+0x20 length:0x28 - 0x20];
            uint64_t datalen = 0;
            [slicedData getBytes:&datalen length:sizeof(datalen)];
            datalen = CFSwapInt64LittleToHost(datalen);
            const UInt8 *datahash_bytes = bytes + ptr;
            datahash = [NSMutableString stringWithCapacity:0x40];
            for (int i = 0; i < 0x20; i++) [datahash appendFormat:@"%02x", datahash_bytes[i]];
            rangeData = [NSData dataWithBytes:bytes + (ptr + 0x28) length:datalen];
            _h[datahash] = [[NSString alloc] initWithData:rangeData encoding:NSUTF8StringEncoding];
            ptr += 0x28 + datalen;
        }
        
        NSString *input = [[NSString alloc] initWithData:rangeData encoding:NSUTF8StringEncoding];
        NSArray *ops = @[@"BufferAlloc", @"BufferFree", @"CopyIn", @"CopyOut", @"ProgramAlloc", @"ProgramFree", @"ProgramExec"];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(%@)\\(", [ops componentsJoinedByString:@"|"]] options:0 error:nil];
        input = [input stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[]"]];
        NSMutableArray *_q = [NSMutableArray array];
        __block NSInteger lastIndex = 0;
        [regex enumerateMatchesInString:input options:0 range:NSMakeRange(0, input.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            if (match.range.location > lastIndex) {
                NSString *substring = [input substringWithRange:NSMakeRange(lastIndex, match.range.location - lastIndex)];
                substring = [substring stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]];
                [_q addObject:substring];
            }
            lastIndex = match.range.location;
        }];
        if (lastIndex < input.length) {
            NSString *substring = [input substringFromIndex:lastIndex];
            substring = [substring stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]];
            [_q addObject:substring];
        }
        NSLog(@"%@", _q);
        NSLog(@"%@", _h);
        
        for (NSString *x in _q) {
            if ([x hasPrefix:@"BufferAlloc"]) {
                NSLog(@"BufferAlloc");
            } else if ([x hasPrefix:@"BufferFree"]) {
                NSLog(@"BufferFree");
            } else if ([x hasPrefix:@"CopyIn"]) {
                NSLog(@"CopyIn");
            } else if ([x hasPrefix:@"CopyOut"]) {
                NSLog(@"CopyOut");
            } else if ([x hasPrefix:@"ProgramAlloc"]) {
                NSLog(@"ProgramAlloc");
                NSString *pattern = @"name='([^']+)'";
                NSRange range = [[[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] firstMatchInString:x options:0 range:NSMakeRange(0, x.length)] rangeAtIndex:1];
                NSString *name = [x substringWithRange:range];
                pattern = @"datahash='([^']+)'";
                range = [[[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] firstMatchInString:x options:0 range:NSMakeRange(0, x.length)] rangeAtIndex:1];
                NSString *datahash = [x substringWithRange:range];
                NSString *prg = _h[datahash];
                
                NSError *error = nil;
                id<MTLLibrary> library = [device newLibraryWithSource:prg
                                                               options:nil
                                                                 error:&error];
                id<MTLFunction> func = [library newFunctionWithName:name];
                MTLComputePipelineDescriptor *descriptor = [[MTLComputePipelineDescriptor alloc] init];
                descriptor.computeFunction = func;
                descriptor.supportIndirectCommandBuffers = YES;
                MTLPipelineOption options = MTLPipelineOptionNone;
                MTLAutoreleasedComputePipelineReflection *reflection = nil;
                id<MTLComputePipelineState> pipeline_state = [device newComputePipelineStateWithDescriptor:descriptor
                                                                      options:options
                                                                   reflection:&reflection
                                                                        error:&error];
                
                [objects setObject:pipeline_state forKey:@[name,datahash]];
                NSLog(@"name = %@",name);
                NSLog(@"prg = %@",prg);
            } else if ([x hasPrefix:@"ProgramFree"]) {
                NSLog(@"ProgramFree");
            } else if ([x hasPrefix:@"ProgramExec"]) {
                NSLog(@"ProgramExec");
            } else {
                NSLog(@"No op found");
            }
        }
        
        NSMutableString *output = [NSMutableString stringWithCapacity:length * 2];
        NSLog(@"%@", output);
        const char *header = "HTTP/1.1 200 OK\r\n"
                             "Content-Type: text/plain\r\n"
                             "Content-Length: 4\r\n"
                             "Connection: close\r\n\r\n";
        const char body[] = {0x00, 'U', '$', 'G'};
        send(handle, header, strlen(header), 0);
        send(handle, body, sizeof(body), 0);
        return;
    }
}
@end
