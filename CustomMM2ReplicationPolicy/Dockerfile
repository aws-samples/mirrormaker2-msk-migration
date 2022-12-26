FROM maven:3.8.6-amazoncorretto-8 as build

WORKDIR /app
COPY ./pom.xml .
RUN mvn verify --fail-never

COPY ./src ./src
RUN mvn package -DskipTests -o


FROM amazoncorretto:8-alpine-jre

WORKDIR /app
COPY --from=build /app/target/CustomMM2ReplicationPolicy-1.0-SNAPSHOT.jar ./CustomMM2ReplicationPolicy.jar

ENTRYPOINT ["java", "-jar", "/app/CustomMM2ReplicationPolicy.jar"]