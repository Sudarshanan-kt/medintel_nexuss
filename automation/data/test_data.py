import os

class TestData:
    # Test users for functional verification
    VALID_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "test-user@medintelnexus.app")
    VALID_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "SecurePass123!")
    
    INVALID_USER_EMAIL = "bad-user@example.com"
    INVALID_USER_PASSWORD = "wrongpassword"
    
    # Mock data payloads
    MOCK_PRESCRIPTION_NAME = "Amoxicillin 500mg"
    MOCK_PATIENT_NAME = "John Doe"
    
    # Security vulnerability testing inputs (safe, benign check patterns)
    SQL_INJECTION_PAYLOADS = [
        "admin' --",
        "1' OR '1'='1",
        "1; DROP TABLE users"
    ]
    
    XSS_PAYLOADS = [
        "<script>alert('xss')</script>",
        "javascript:alert(1)",
        "<img src=x onerror=alert(1)>"
    ]
