# --- Stage 1: Build ---
FROM gcc:latest as builder

WORKDIR /src

# Copy the C source code
COPY stack_server.c .

# Compile statically
# -static: bundles libraries into the executable so it runs on Alpine
# -o stack_server: output filename
RUN gcc -o stack_server stack_server.c -static

# --- Stage 2: Run ---
FROM alpine:latest

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /src/stack_server .

# Expose the port defined in the C code
EXPOSE 5001

# Run the binary
CMD ["./stack_server"]