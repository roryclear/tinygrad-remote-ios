#import "ViewController.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self startServer];
    });
}

- (void)startServer {
    int serverSocket = socket(PF_INET, SOCK_STREAM, 0);

    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(6667); //tinygrad port
    serverAddr.sin_addr.s_addr = INADDR_ANY;

    if (bind(serverSocket, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        perror("Error: Unable to bind socket");
        close(serverSocket);
        return;
    }

    if (listen(serverSocket, 5) < 0) {
        perror("Error: Unable to listen");
        close(serverSocket);
        return;
    }

    NSLog(@"Server running on port 6667");
    
    while (1) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSocket = accept(serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientSocket < 0) {
            perror("Error: Unable to accept connection");
            continue;
        }

        [self handleClient:clientSocket];
        close(clientSocket);
    }
}

- (void)handleClient:(int)clientSocket {
    char buffer[1024];
    ssize_t bytesRead = read(clientSocket, buffer, sizeof(buffer) - 1);
    if (bytesRead > 0) {
        buffer[bytesRead] = '\0';
        NSString *request = [NSString stringWithUTF8String:buffer];
        NSRange range = [request rangeOfString:@"GET /renderer "];
        
        if (range.location != NSNotFound) {
            NSLog(@"/renderer");
            NSString *responseBody = @"[\"tinygrad.renderer.cstyle\", \"MetalRenderer\", []]";
            NSString *responseHeader = [NSString stringWithFormat:
                                        @"HTTP/1.1 200 OK\r\n"
                                         "Content-Type: application/json\r\n"
                                         "Content-Length: %lu\r\n"
                                         "\r\n",
                                        (unsigned long)[responseBody length]];
            write(clientSocket, [responseHeader UTF8String], [responseHeader length]);
            write(clientSocket, [responseBody UTF8String], [responseBody length]);
        }
    }
}

@end


