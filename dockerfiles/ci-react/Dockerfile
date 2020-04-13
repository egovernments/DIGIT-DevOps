FROM egovio/ci-react:0.0.2

RUN npm install n -g

RUN n 8.15.0
RUN rm /usr/local/bin/yarn
RUN npm i yarn -g
RUN npm install lerna -g
