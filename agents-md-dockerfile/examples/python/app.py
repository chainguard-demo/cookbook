#!/usr/bin/env python3
import MySQLdb

print(f"MySQLdb client info: {MySQLdb.get_client_info()}")
print(f"MySQLdb threadsafety: {MySQLdb.threadsafety}")
print(f"MySQLdb version info: {MySQLdb.version_info}")
print("Hello from Chainguard Python image!")
