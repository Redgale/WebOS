FROM node:22-slim

# Install Docker and other dependencies
RUN apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io

WORKDIR /app
COPY . .

# Make setup script executable and run it
RUN chmod +x setup.sh && ./setup.sh

# Install npm dependencies
RUN npm install

# Set your start command
CMD ["npm", "start"]
