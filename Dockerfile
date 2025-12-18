# 1. Use the official Julia image
FROM julia:1.10

# 2. Set the working directory inside the container
WORKDIR /app

# 3. Copy Project.toml and Manifest.toml first (for caching)
COPY Project.toml ./
 # Manifest.toml ./

# 4. Install dependencies
# This step builds the packages inside the container
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# 5. Copy the rest of the application code
COPY . .

# 6. Expose the port (Render usually uses 10000, but we bind to $PORT)
ENV PORT=8080
EXPOSE 8080

# 7. Start the app
# "web" matches your Procfile, or we can run directly:
CMD ["julia", "--project=.", "src/ISO13373.jl"]