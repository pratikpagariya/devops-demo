###############################################################################
# Pre-baked Jenkins controller image.
# Plugins are installed at BUILD time (jenkins-plugin-cli) into the reference
# directory, so the running pod downloads NOTHING at startup. This permanently
# eliminates the boot-time "HTTP 503 while downloading plugins" crashloop.
#
# Build + push to ECR, then point controller.image in jenkins.values.yaml at it
# and set controller.installPlugins: false (already done in that file).
###############################################################################
FROM jenkins/jenkins:2.504.1-jdk17

# Install plugins at build time. A 503 here just means re-run `docker build`
# (off the cluster, Docker-layer-cached) — it never affects the running pod.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Config is managed via Helm/JCasC — skip the interactive setup wizard.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
