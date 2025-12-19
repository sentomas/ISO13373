# 1. Use Julia Image
FROM julia:1.10

# 2. Setup App Directory
WORKDIR /app

# 3. Copy Project Definitions
COPY Project.toml Manifest.toml ./

# --- SAFETY FIX ---
# Delete the Windows-generated Manifest so we build a fresh one for Linux
RUN rm -f Manifest.toml

# 4. Install Dependencies
# This forces a fresh resolve of all packages
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.resolve(); Pkg.precompile()'

# 5. Copy Source Code
COPY . .

# 6. Expose Port
ENV PORT=8080
EXPOSE 8080

# 7. Start the App
CMD ["julia", "--project=.", "src/ISO13373.jl"]