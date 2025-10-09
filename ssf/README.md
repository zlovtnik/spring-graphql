<div align="center">
  <h1>🚀 Spring Boot GraphQL API</h1>
  <p>
    <a href="https://spring.io/projects/spring-boot">
      <img alt="Spring Boot" src="https://img.shields.io/badge/Spring%20Boot-6DB33F?style=for-the-badge&logo=springboot&logoColor=white" />
    </a>
    <a href="https://graphql.org/">
      <img alt="GraphQL" src="https://img.shields.io/badge/GraphQL-E10098?style=for-the-badge&logo=graphql&logoColor=white" />
    </a>
    <a href="https://www.sqlite.org/">
      <img alt="SQLite" src="https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white" />
    </a>
  </p>
  
  <p>Modern GraphQL API built with Spring Boot, featuring JWT authentication, MinIO integration, and more.</p>
</div>

## 📋 Table of Contents
- [✨ Features](#-features)
- [🚀 Quick Start](#-quick-start)
- [⚙️ Configuration](#️-configuration)
- [🔧 Development](#-development)
- [🔒 Security](#-security)
- [📊 API Documentation](#-api-documentation)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

## ✨ Features

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Feature</b></td>
      <td align="center"><b>Status</b></td>
      <td align="center"><b>Description</b></td>
    </tr>
    <tr>
      <td>🚀 GraphQL API</td>
      <td>✅ Ready</td>
      <td>Modern GraphQL API with type-safe queries and mutations</td>
    </tr>
    <tr>
      <td>💾 SQLite Database</td>
      <td>✅ Ready</td>
      <td>Lightweight, file-based database for local development</td>
    </tr>
    <tr>
      <td>🔒 JWT Authentication</td>
      <td>🔧 In Progress</td>
      <td>Secure token-based authentication</td>
    </tr>
    <tr>
      <td>📦 MinIO Integration</td>
      <td>🔧 In Progress</td>
      <td>Object storage for files and media</td>
    </tr>
    <tr>
      <td>🔐 HTTPS Support</td>
      <td>✅ Ready</td>
      <td>Secure communication with SSL/TLS</td>
    </tr>
  </table>
</div>

## 🚀 Quick Start

### Prerequisites
- Java 17+
- Gradle 7.0+
- (Optional) Docker for MinIO

### Running the Application

```bash
# Clone the repository
git clone https://github.com/yourusername/ssf.git
cd ssf

# Build the application
./gradlew build

# Run the application
./gradlew bootRun
```

The application will be available at:  
🌐 **GraphQL Playground**: [http://localhost:8080/graphiql](http://localhost:8080/graphiql)  
🔌 **GraphQL Endpoint**: [http://localhost:8080/graphql](http://localhost:8080/graphql)

## ⚙️ Configuration

Configuration can be managed through `application.properties` or environment variables:

```properties
# Server Configuration
server.port=8080
server.ssl.enabled=true

# Database Configuration
spring.datasource.url=jdbc:sqlite:./data/ssf.db
spring.datasource.driver-class-name=org.sqlite.JDBC

# JWT Configuration (update with your own values)
jwt.secret=your-secret-key
jwt.expiration=86400000

# MinIO Configuration
minio.url=http://localhost:9000
minio.access-key=your-access-key
minio.secret-key=your-secret-key
minio.bucket-name=ssf-files
```

## 🔧 Development

### Project Structure

```
src/
├── main/
│   ├── java/
│   │   └── com/example/ssf/
│   │       ├── config/       # Configuration classes
│   │       ├── controller/   # GraphQL controllers
│   │       ├── model/        # Data models
│   │       ├── repository/   # Data repositories
│   │       ├── security/     # Security configuration
│   │       └── service/      # Business logic
│   └── resources/
│       ├── graphql/         # GraphQL schema files
│       └── application.properties
└── test/                    # Test files
```

### Building and Testing

```bash
# Run tests
./gradlew test

# Build the application
./gradlew build

# Run with custom profile
SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun
```

## 🔒 Security

This application implements JWT-based authentication. To secure your endpoints:

1. Obtain a token from the authentication endpoint
2. Include the token in the `Authorization` header: `Bearer <token>`

## 📊 API Documentation

Explore the GraphQL API using the built-in GraphiQL interface at [http://localhost:8080/graphiql](http://localhost:8080/graphiql)

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  Made with ❤️ and Spring Boot
</div>
