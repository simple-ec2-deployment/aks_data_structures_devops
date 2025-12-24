#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

#define PORT 5001
#define BUFFER_SIZE 4096

// --- Data Structure: Stack ---
int stack[100];
int top = -1;

void stack_push(int val) {
    if (top < 99) {
        stack[++top] = val;
    }
}

int stack_pop() {
    if (top < 0) return -1;
    return stack[top--];
}

int stack_peek() {
    if (top < 0) return -1;
    return stack[top];
}

// --- Main Server Logic ---
int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[BUFFER_SIZE] = {0};

    // 1. Create Socket File Descriptor
    // AF_INET = IPv4, SOCK_STREAM = TCP
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    // 2. Attach socket to the port 5001 (and allow reuse of port)
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY; // Listen on 0.0.0.0
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    // 3. Start Listening
    if (listen(server_fd, 5) < 0) {
        perror("Listen");
        exit(EXIT_FAILURE);
    }

    printf("Pure C Stack Server listening on port %d\n", PORT);

    // 4. Accept Loop
    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("Accept");
            continue;
        }

        // Read the incoming HTTP Request
        read(new_socket, buffer, BUFFER_SIZE);

        char response_body[256];

        // --- Manual HTTP Routing & Parsing ---

        // Route 1: POST /push?val=123
        if (strstr(buffer, "POST /push") != NULL) {
            // Find "val=" in the query string
            char *val_ptr = strstr(buffer, "val=");
            int val = 0;
            if (val_ptr) {
                // Parse the number after "val="
                val = atoi(val_ptr + 4);
                stack_push(val);
                sprintf(response_body, "{\"status\": \"pushed\", \"value\": %d, \"top\": %d}", val, top);
            } else {
                sprintf(response_body, "{\"error\": \"missing value parameter\"}");
            }
        }
        // Route 2: GET /pop
        else if (strstr(buffer, "GET /pop") != NULL) {
            int val = stack_pop();
            if (val == -1) {
                 sprintf(response_body, "{\"status\": \"empty\", \"value\": null}");
            } else {
                 sprintf(response_body, "{\"status\": \"popped\", \"value\": %d}", val);
            }
        }
        // Default Route (Health Check)
        else {
            sprintf(response_body, "{\"message\": \"C Stack Server Alive\", \"size\": %d}", top + 1);
        }

        // --- Construct HTTP Response ---
        char response_header[512];
        sprintf(response_header,
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: application/json\r\n"
            "Content-Length: %ld\r\n"
            "Connection: close\r\n"
            "\r\n", strlen(response_body));

        // Send Header then Body
        send(new_socket, response_header, strlen(response_header), 0);
        send(new_socket, response_body, strlen(response_body), 0);

        // Close connection immediately (Stateless HTTP)
        close(new_socket);

        // Clear buffer for next request
        memset(buffer, 0, BUFFER_SIZE);
    }

    return 0;
}