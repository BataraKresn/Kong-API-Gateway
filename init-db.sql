-- Initialize separate databases for Kong and Konga
-- This script runs automatically when PostgreSQL container starts for the first time

-- Create Kong database
CREATE DATABASE kong;

-- Create Konga database  
CREATE DATABASE konga;

-- Grant privileges to the default user for both databases
GRANT ALL PRIVILEGES ON DATABASE kong TO postgres;
GRANT ALL PRIVILEGES ON DATABASE konga TO postgres;

-- Connect to konga database to create required tables
\c konga;

-- Konga will auto-create its own tables when starting up
-- No need to create tables manually

-- Grant permissions on new tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;

-- Display created databases for verification
\c postgres;
\l
