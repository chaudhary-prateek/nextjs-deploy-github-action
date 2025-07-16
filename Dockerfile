# Use Node.js base image
FROM node:18-alpine

# Set working directory
#WORKDIR /app
WORKDIR /var/www/html

# ✅ Install pnpm
RUN npm install -g pnpm

# Install dependencies
COPY package.json pnpm-lock.yaml ./
#RUN npm install -g pnpm && pnpm install
RUN pnpm install

# Copy app source code and .env file
COPY .env .env

COPY . .

# ✅ Build Next.js app (uses .env vars at build time)
RUN pnpm run build

# Clean up .env (optional)
RUN rm .env

# Expose app port
EXPOSE 3000

# Start the app
CMD ["pnpm", "start"]


