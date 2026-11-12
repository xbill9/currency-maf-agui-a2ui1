# The Agent Framework agent and its MCP server (a stdio child process) in one
# container, serving AG-UI on 8080. Azure Container Apps runs it behind
# internal ingress; only the UI app reaches it.
FROM python:3.14-slim
WORKDIR /app
COPY pyproject.toml ./
# Install the dependencies pyproject.toml lists, without building this directory as a package.
RUN python3 -c 'import tomllib,subprocess,sys; d=tomllib.load(open("pyproject.toml","rb"))["project"]["dependencies"]; subprocess.check_call([sys.executable,"-m","pip","install","--no-cache-dir",*d])'
COPY . .
ENV PORT=8080 PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["python3", "main.py"]
