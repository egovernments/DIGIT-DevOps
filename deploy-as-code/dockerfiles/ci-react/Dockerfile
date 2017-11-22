FROM egovio/ci-react:0.0.2

ADD package.json /tmp/package.json

RUN cd /tmp && npm install

RUN npm install -g npx

COPY ./npmrc /tmp/.npmrc
