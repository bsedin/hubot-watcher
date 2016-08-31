FROM cataska/hubot-slack

MAINTAINER Alexey Kuznetsov <me@kuznetsoff.io>

RUN npm install hubot-watcher --save

RUN echo '[ \
  "hubot-watcher" \
]' > hubot/external-scripts.json
