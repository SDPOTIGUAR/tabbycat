# Docker file lists all the commands needed to setup a fresh linux instance to
# run the application specified. docker-compose does not use this.

# Grab a python image
FROM python:3.11

# Just needed for all things python (note this is setting an env variable)
ENV PYTHONUNBUFFERED 1
# Needed for correct settings input
ENV IN_DOCKER 1

# Setup Node/NPM
RUN apt-get update
RUN apt-get install -y curl nginx
ENV NVM_DIR="/root/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Copy all our files into the baseimage and cd to that directory
WORKDIR /tcd
COPY . /tcd/

# Symlink into a stable PATH location: RUN layers don't inherit each
# other's shell state (nvm's PATH tweak), and podman's OCI build format
# ignores the SHELL instruction some other Dockerfiles rely on for this.
# Note: sourcing nvm.sh alone exits non-zero (it silently attempts an
# auto `nvm use` with nothing installed yet), so it can't be chained
# with && - it needs its own statement before nvm install runs.
RUN bash -c '. "$NVM_DIR/nvm.sh"; \
    nvm install \
    && nvm use \
    && ln -sf "$(nvm which current)" /usr/local/bin/node \
    && ln -sf "$(dirname "$(nvm which current)")/npm" /usr/local/bin/npm \
    && ln -sf "$(dirname "$(nvm which current)")/npx" /usr/local/bin/npx'

# Set git to use HTTPS (SSH is often blocked by firewalls)
RUN git config --global url."https://".insteadOf git://

# Install our node/python requirements
RUN pip install pipenv
# --deploy would hard-fail here: this tag's Pipfile.lock hash is stale
# against its own Pipfile. bin/render-compile.sh (what Render actually
# runs) already installs without --deploy, so this just matches that.
RUN pipenv install --system
RUN npm ci --only=production

# Compile all the static files
RUN npm run build
RUN python ./tabbycat/manage.py collectstatic --noinput -v 0
