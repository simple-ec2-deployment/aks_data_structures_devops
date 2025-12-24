import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;

public class LinkedListService {

    // --- Data Structure: Node ---
    static class Node {
        String data;
        Node prev;
        Node next;

        public Node(String data) {
            this.data = data;
        }
    }

    // --- Data Structure: Doubly Linked List ---
    static class DoublyLinkedList {
        Node head, tail;

        // Add to the end
        void add(String data) {
            Node newNode = new Node(data);
            if (head == null) {
                head = tail = newNode;
            } else {
                tail.next = newNode;
                newNode.prev = tail;
                tail = newNode;
            }
            // Limit size for the demo so the UI doesn't get huge
            if (size() > 8) removeFirst();
        }

        void removeFirst() {
            if (head == null) return;
            if (head == tail) {
                head = tail = null;
            } else {
                head = head.next;
                head.prev = null;
            }
        }

        int size() {
            int count = 0;
            Node current = head;
            while(current != null) { count++; current = current.next; }
            return count;
        }

        // Return string representation: [ A <-> B <-> C ]
        public String toString() {
            if (head == null) return "[ Empty ]";
            StringBuilder sb = new StringBuilder("[ ");
            Node current = head;
            while (current != null) {
                sb.append(current.data);
                if (current.next != null) sb.append(" <-> ");
                current = current.next;
            }
            sb.append(" ]");
            return sb.toString();
        }
    }

    static DoublyLinkedList list = new DoublyLinkedList();

    public static void main(String[] args) throws IOException {
        // Create server on Port 5002
        HttpServer server = HttpServer.create(new InetSocketAddress(5002), 0);

        // Endpoint: /add?val=XYZ
        server.createContext("/add", (exchange) -> {
            String query = exchange.getRequestURI().getQuery();
            String val = "NoData";
            if (query != null && query.contains("val=")) {
                val = query.split("=")[1];
            }

            list.add(val);

            String response = "Added: " + val;
            sendResponse(exchange, 200, response);
        });

        // Endpoint: /display
        server.createContext("/display", (exchange) -> {
            String response = list.toString();
            sendResponse(exchange, 200, response);
        });

        server.setExecutor(null); // creates a default executor
        server.start();
        System.out.println("Java Linked List Service running on port 5002");
    }

    private static void sendResponse(HttpExchange exchange, int statusCode, String response) throws IOException {
        exchange.sendResponseHeaders(statusCode, response.length());
        OutputStream os = exchange.getResponseBody();
        os.write(response.getBytes());
        os.close();
    }
}