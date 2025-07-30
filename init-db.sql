-- Initialize separate databases for Kong and Konga
-- This script runs automatically when PostgreSQL container starts for the first time

-- Create Kong database
CREATE DATABASE kong;

-- Create Konga database  
CREATE DATABASE konga;

-- Grant privileges to the default user for both databases
GRANT ALL PRIVILEGES ON DATABASE kong TO postgres;
GRANT ALL PRIVILEGES ON DATABASE konga TO postgres;

-- Display created databases for verification
\l
