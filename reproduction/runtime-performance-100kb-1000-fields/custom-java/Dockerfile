FROM eclipse-temurin:21-jre
WORKDIR /opt/flowplane-benchmark
COPY target/custom-java-json-runtime.jar /opt/flowplane-benchmark/runtime.jar
ENTRYPOINT ["java", "-jar", "/opt/flowplane-benchmark/runtime.jar"]
