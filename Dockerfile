# Use the official Nginx image as the base image
FROM nginx:latest

# Set the working directory to the Nginx web root
WORKDIR /usr/share/nginx/html

# Copy the contents of the local 'html' directory into the container at the working directory
COPY index.html .

# Expose port 80 to the outside world
EXPOSE 8081

# Command to start Nginx when the container runs
CMD ["nginx", "-g", "daemon off;"]
