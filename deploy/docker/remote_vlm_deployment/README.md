# Remote VLM Deployment Setup

## Environment Configuration

1. Copy the template file to create your local environment configuration:
   ```bash
   cp .env.template .env
   ```

2. Edit the `.env` file and replace the placeholder values with your actual API keys:
   - `OPENAI_API_KEY`: Your OpenAI API key (starts with `sk-`)
   - `NVIDIA_API_KEY`: Your NVIDIA API key (starts with `nvapi-`)
   - `NGC_API_KEY`: Your NGC API key (if using jupyter notebooks)

3. Update other configuration values as needed for your deployment.

## Security Notes

- **Never commit the `.env` file to version control** - it contains sensitive API keys
- The `.env` file is already included in `.gitignore`
- Use the `.env.template` file as a reference for required environment variables

## Running the Deployment

After setting up your `.env` file, you can run the deployment using:

```bash
docker-compose up -d
``` 