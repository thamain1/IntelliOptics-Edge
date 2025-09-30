# Compatibility shim: old code does `from model import ...`
from app.core.configs import *  # re-export all symbols so legacy imports keep working
