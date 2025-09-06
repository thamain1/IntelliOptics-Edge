from fastapi import Request

async def require_auth(request: Request):
    # TODO: validate JWTs from Azure AD via JWKS in production
    return
