# Use a standard Java 17 image that exists on Docker Hub
FROM eclipse-temurin:17-jdk-jammy

WORKDIR /app

# Copy the source code
COPY LinkedListService.java .

# Compile the Java code
RUN javac LinkedListService.java

# Expose the port defined in the code
EXPOSE 5002

# Run the compiled class
CMD ["java", "LinkedListService"]
