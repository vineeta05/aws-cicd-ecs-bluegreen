package com.demo;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;

public class App {

    public static void main(String[] args) throws IOException {
        int port = 8080;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/", new RootHandler());
        server.createContext("/health", new HealthHandler());
        server.createContext("/version", new VersionHandler());

        server.setExecutor(null);
        server.start();
        System.out.println("Server started on port " + port);
    }

    // Root Handler
    static class RootHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String response = "{\"message\": \"Hello from Java CI/CD Demo!\", \"status\": \"running\"}";
            sendResponse(exchange, 200, response);
        }
    }

    // Health Check Handler — used by ECS ALB Target Group
    static class HealthHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String response = "{\"status\": \"UP\"}";
            sendResponse(exchange, 200, response);
        }
    }

    // Version Handler
    static class VersionHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            String version = System.getenv("APP_VERSION") != null ? System.getenv("APP_VERSION") : "1.0.0";
            String response = "{\"version\": \"" + version + "\"}";
            sendResponse(exchange, 200, response);
        }
    }

    // Utility
    static void sendResponse(HttpExchange exchange, int statusCode, String body) throws IOException {
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(statusCode, body.length());
        OutputStream os = exchange.getResponseBody();
        os.write(body.getBytes());
        os.close();
    }
}
