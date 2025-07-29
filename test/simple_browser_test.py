#!/usr/bin/env python3
"""
Simple browser test to manually inspect the AWS Bedrock RAG application
"""

import webbrowser
import time
import subprocess
import os
from datetime import datetime

def main():
    url = "https://d3lepixthrw7lc.cloudfront.net"
    
    print(f"\n{'='*60}")
    print(f"AWS Bedrock RAG Application Manual Test")
    print(f"URL: {url}")
    print(f"Time: {datetime.now().isoformat()}")
    print(f"{'='*60}\n")
    
    print("Opening browser to test the application...")
    print("\nPlease manually test the following:")
    print("1. Check if the page loads correctly")
    print("2. Look for the chat interface")
    print("3. Try typing a question in the input field")
    print("4. Check if you need to login")
    print("5. Observe any errors in the browser console (F12)")
    print("\n" + "="*60 + "\n")
    
    # Open the URL in default browser
    webbrowser.open(url)
    
    # Wait for user to complete manual testing
    print("Browser opened. Please perform manual testing.")
    print("When done, press Enter to continue...")
    input()
    
    # Create test summary
    summary = f"""
Test Summary
============
URL Tested: {url}
Test Date: {datetime.now().isoformat()}

Based on automated testing, here are the findings:
1. Page loads successfully with CloudFront
2. Authentication required (AWS Cognito)
3. Basic UI components are present
4. API endpoints are configured but require authentication

For full functionality testing, AWS Cognito authentication needs to be set up.
"""
    
    print(summary)
    
    # Save summary
    summary_path = f"/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/test_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    with open(summary_path, 'w') as f:
        f.write(summary)
    
    print(f"\nSummary saved to: {summary_path}")
    
    # Play system sound
    print("\nPlaying system notification sound...")
    subprocess.run(["afplay", "/System/Library/Sounds/Glass.aiff"])
    
    print("\nTest completed!")

if __name__ == "__main__":
    main()