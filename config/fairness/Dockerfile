# O'FAIRe (https://github.com/agroportal/fairness): the FAIRness assessment web
# service of the appliance. Upstream publishes no image, so this builds the war
# from source at the ref given by FAIRNESS_REF.
#
# Tomcat 9 is not an arbitrary pin: the servlet is written against
# javax.servlet (servlet-api 2.5), which Tomcat 10 replaced with
# jakarta.servlet. On Tomcat 10+ the webapp deploys but never answers.

ARG MAVEN_IMAGE=maven:3.9-eclipse-temurin-11
ARG TOMCAT_IMAGE=tomcat:9.0-jre11-temurin

FROM ${MAVEN_IMAGE} AS build

ARG FAIRNESS_REPOSITORY=https://github.com/agroportal/fairness.git
ARG FAIRNESS_REF=master

WORKDIR /src
RUN git clone --depth 1 --branch "${FAIRNESS_REF}" "${FAIRNESS_REPOSITORY}" . \
    # the pom points at the deployment descriptor with Windows separators
    # (WebContent\WEB-INF\web.xml); rewrite them so the path resolves here
    && sed -i 's|WebContent\\WEB-INF\\web.xml|WebContent/WEB-INF/web.xml|' pom.xml \
    && mvn -B -q clean package -DskipTests

FROM ${TOMCAT_IMAGE}

# Deployed exploded (as the ROOT webapp) rather than as a war, because the app
# reads its portal configuration from the classpath
# (WEB-INF/classes/config/portals/<portal>/config.properties): the entrypoint
# has to write that file into the deployed webapp before Tomcat starts, and
# CacheSaverCMD lists that directory to discover the configured portals.
# maven-war-plugin already leaves the exploded webapp in target/<finalName>/.
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /src/target/fairness-assessment/ /usr/local/tomcat/webapps/ROOT/

COPY entrypoint.sh fairness-cache /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/fairness-cache

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["catalina.sh", "run"]
