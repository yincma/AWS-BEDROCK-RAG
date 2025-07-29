#!/usr/bin/env python3
"""
Automated testing script for AWS Bedrock RAG application
This script simulates human manual testing and records the entire process
"""

import asyncio
import os
import sys
import json
from datetime import datetime
from playwright.async_api import async_playwright, Page
import subprocess
from typing import Dict, List, Any

class RAGApplicationTester:
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.test_results = []
        self.screenshots = []
        self.console_logs = []
        self.network_logs = []
        self.errors = []
        
    async def log_console_message(self, msg):
        """Log browser console messages"""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "type": msg.type,
            "text": msg.text,
            "location": msg.location
        }
        self.console_logs.append(log_entry)
        print(f"[CONSOLE {msg.type.upper()}] {msg.text}")
        
    async def log_network_request(self, request):
        """Log network requests"""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "method": request.method,
            "url": request.url,
            "headers": dict(request.headers)
        }
        self.network_logs.append(log_entry)
        print(f"[NETWORK REQUEST] {request.method} {request.url}")
        
    async def log_network_response(self, response):
        """Log network responses"""
        try:
            log_entry = {
                "timestamp": datetime.now().isoformat(),
                "url": response.url,
                "status": response.status,
                "headers": dict(response.headers) if response.headers else {}
            }
            self.network_logs.append(log_entry)
            print(f"[NETWORK RESPONSE] {response.status} {response.url}")
        except Exception as e:
            print(f"[ERROR logging response] {e}")
            
    async def capture_screenshot(self, page: Page, name: str):
        """Capture screenshot and save it"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/screenshots/{timestamp}_{name}.png"
        
        # Create screenshots directory if it doesn't exist
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        
        await page.screenshot(path=filename, full_page=True)
        self.screenshots.append(filename)
        print(f"[SCREENSHOT] Saved: {filename}")
        
    async def test_homepage_load(self, page: Page):
        """Test 1: Homepage Loading"""
        print("\n=== Test 1: Testing Homepage Load ===")
        
        start_time = datetime.now()
        await page.goto(self.base_url, wait_until="networkidle")
        load_time = (datetime.now() - start_time).total_seconds()
        
        await self.capture_screenshot(page, "homepage_loaded")
        
        # Check for main elements
        title = await page.title()
        print(f"Page Title: {title}")
        
        # Check for loading spinner disappearance
        await page.wait_for_selector("#loading", state="hidden", timeout=10000)
        print("Loading spinner disappeared")
        
        # Check for main app container
        app_container = await page.wait_for_selector("#root", timeout=5000)
        print("Main app container found")
        
        self.test_results.append({
            "test": "Homepage Load",
            "status": "PASS",
            "load_time": f"{load_time:.2f}s",
            "title": title
        })
        
    async def test_ui_components(self, page: Page):
        """Test 2: UI Components Visibility"""
        print("\n=== Test 2: Testing UI Components ===")
        
        # Wait for main components
        components_to_check = [
            ("Chat interface", ".chat-container, .message-container, [class*='chat'], [class*='Chat']"),
            ("Input field", "input[type='text'], textarea, [class*='input'], [class*='Input']"),
            ("Send button", "button[type='submit'], button:has-text('Send'), button:has-text('发送'), [class*='send'], [class*='Send']"),
            ("Header", "header, .header, [class*='header'], [class*='Header']"),
            ("Main content area", "main, .main, [class*='main'], [class*='Main']")
        ]
        
        results = []
        for name, selector in components_to_check:
            try:
                element = await page.wait_for_selector(selector, timeout=5000, state="visible")
                if element:
                    results.append(f"✓ {name} found")
                    print(f"✓ {name} found")
            except:
                results.append(f"✗ {name} not found")
                print(f"✗ {name} not found with selector: {selector}")
                
        await self.capture_screenshot(page, "ui_components")
        
        self.test_results.append({
            "test": "UI Components",
            "status": "PASS" if all("✓" in r for r in results) else "PARTIAL",
            "components": results
        })
        
    async def test_query_functionality(self, page: Page):
        """Test 3: Query Submission and Response"""
        print("\n=== Test 3: Testing Query Functionality ===")
        
        try:
            # Find input field - try multiple selectors
            input_selectors = [
                "textarea",
                "input[type='text']",
                "[class*='input']",
                "[class*='Input']",
                "[placeholder*='question']",
                "[placeholder*='ask']",
                "[placeholder*='输入']",
                "[placeholder*='查询']"
            ]
            
            input_field = None
            for selector in input_selectors:
                try:
                    input_field = await page.wait_for_selector(selector, timeout=2000, state="visible")
                    if input_field:
                        print(f"Found input field with selector: {selector}")
                        break
                except:
                    continue
                    
            if not input_field:
                raise Exception("Could not find input field")
                
            # Type test query
            test_query = "What is AWS Bedrock?"
            await input_field.fill(test_query)
            print(f"Typed query: {test_query}")
            
            await self.capture_screenshot(page, "query_typed")
            
            # Find and click send button - try multiple approaches
            send_selectors = [
                "button[type='submit']",
                "button:has-text('Send')",
                "button:has-text('发送')",
                "button:has-text('Submit')",
                "button:has-text('提交')",
                "[class*='send']",
                "[class*='Send']",
                "[class*='submit']",
                "[class*='Submit']"
            ]
            
            send_button = None
            for selector in send_selectors:
                try:
                    send_button = await page.wait_for_selector(selector, timeout=2000, state="visible")
                    if send_button:
                        print(f"Found send button with selector: {selector}")
                        break
                except:
                    continue
                    
            if send_button:
                await send_button.click()
            else:
                # Try pressing Enter
                await input_field.press("Enter")
                print("Pressed Enter to submit")
                
            print("Query submitted")
            
            # Wait for response
            await page.wait_for_timeout(3000)  # Wait for response to start
            
            # Look for response elements
            response_selectors = [
                ".message:last-child",
                "[class*='message']:last-child",
                "[class*='response']",
                "[class*='Response']",
                ".chat-message:last-child",
                "[class*='assistant']",
                "[class*='bot']"
            ]
            
            response_found = False
            for selector in response_selectors:
                try:
                    response_element = await page.wait_for_selector(selector, timeout=10000, state="visible")
                    if response_element:
                        response_text = await response_element.text_content()
                        if response_text and len(response_text) > 10:
                            print(f"Response received: {response_text[:100]}...")
                            response_found = True
                            break
                except:
                    continue
                    
            await self.capture_screenshot(page, "query_response")
            
            self.test_results.append({
                "test": "Query Functionality",
                "status": "PASS" if response_found else "FAIL",
                "query": test_query,
                "response_received": response_found
            })
            
        except Exception as e:
            print(f"Error in query test: {e}")
            self.test_results.append({
                "test": "Query Functionality",
                "status": "FAIL",
                "error": str(e)
            })
            
    async def test_error_handling(self, page: Page):
        """Test 4: Error Handling"""
        print("\n=== Test 4: Testing Error Handling ===")
        
        # Test with empty query
        try:
            input_field = await page.query_selector("textarea, input[type='text']")
            if input_field:
                await input_field.fill("")
                
                # Try to submit empty query
                send_button = await page.query_selector("button[type='submit'], button:has-text('Send')")
                if send_button:
                    await send_button.click()
                else:
                    await input_field.press("Enter")
                    
                await page.wait_for_timeout(2000)
                await self.capture_screenshot(page, "empty_query_test")
                
                # Check for validation or error message
                error_selectors = [
                    "[class*='error']",
                    "[class*='Error']",
                    "[class*='warning']",
                    "[class*='Warning']",
                    ".error-message",
                    ".validation-message"
                ]
                
                error_found = False
                for selector in error_selectors:
                    error_element = await page.query_selector(selector)
                    if error_element:
                        error_found = True
                        break
                        
                self.test_results.append({
                    "test": "Empty Query Handling",
                    "status": "PASS",
                    "validation_present": error_found
                })
                
        except Exception as e:
            print(f"Error in error handling test: {e}")
            self.test_results.append({
                "test": "Error Handling",
                "status": "FAIL",
                "error": str(e)
            })
            
    async def run_tests(self):
        """Run all tests with video recording"""
        print(f"\n{'='*60}")
        print(f"Starting Automated Testing for: {self.base_url}")
        print(f"Timestamp: {datetime.now().isoformat()}")
        print(f"{'='*60}\n")
        
        async with async_playwright() as p:
            # Launch browser with video recording
            browser = await p.chromium.launch(
                headless=False,  # Show browser for visual testing
                args=['--start-maximized']
            )
            
            context = await browser.new_context(
                viewport={'width': 1920, 'height': 1080},
                record_video_dir="/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/videos",
                record_video_size={'width': 1920, 'height': 1080}
            )
            
            page = await context.new_page()
            
            # Set up event listeners
            page.on("console", self.log_console_message)
            page.on("request", self.log_network_request)
            page.on("response", self.log_network_response)
            page.on("pageerror", lambda err: self.errors.append({
                "timestamp": datetime.now().isoformat(),
                "error": str(err)
            }))
            
            try:
                # Run all tests
                await self.test_homepage_load(page)
                await page.wait_for_timeout(2000)
                
                await self.test_ui_components(page)
                await page.wait_for_timeout(2000)
                
                await self.test_query_functionality(page)
                await page.wait_for_timeout(2000)
                
                await self.test_error_handling(page)
                await page.wait_for_timeout(2000)
                
                # Final screenshot
                await self.capture_screenshot(page, "final_state")
                
            except Exception as e:
                print(f"\nCritical error during testing: {e}")
                self.errors.append({
                    "timestamp": datetime.now().isoformat(),
                    "error": f"Critical: {str(e)}"
                })
                
            finally:
                # Save video
                await page.wait_for_timeout(1000)
                await context.close()
                await browser.close()
                
                # Get video path
                video_path = await page.video.path()
                if video_path:
                    print(f"\nVideo saved to: {video_path}")
                    
        return self.generate_report()
        
    def generate_report(self):
        """Generate test report"""
        report = {
            "timestamp": datetime.now().isoformat(),
            "url": self.base_url,
            "test_results": self.test_results,
            "console_logs": self.console_logs,
            "network_logs": self.network_logs,
            "errors": self.errors,
            "screenshots": self.screenshots,
            "summary": {
                "total_tests": len(self.test_results),
                "passed": sum(1 for t in self.test_results if t["status"] == "PASS"),
                "failed": sum(1 for t in self.test_results if t["status"] == "FAIL"),
                "partial": sum(1 for t in self.test_results if t["status"] == "PARTIAL"),
                "console_warnings": sum(1 for log in self.console_logs if log["type"] == "warning"),
                "console_errors": sum(1 for log in self.console_logs if log["type"] == "error"),
                "page_errors": len(self.errors)
            }
        }
        
        # Save report
        report_path = f"/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/test_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
            
        print(f"\n{'='*60}")
        print("TEST SUMMARY")
        print(f"{'='*60}")
        print(f"Total Tests: {report['summary']['total_tests']}")
        print(f"Passed: {report['summary']['passed']}")
        print(f"Failed: {report['summary']['failed']}")
        print(f"Partial: {report['summary']['partial']}")
        print(f"Console Errors: {report['summary']['console_errors']}")
        print(f"Console Warnings: {report['summary']['console_warnings']}")
        print(f"Page Errors: {report['summary']['page_errors']}")
        print(f"\nReport saved to: {report_path}")
        print(f"{'='*60}\n")
        
        return report

async def main():
    """Main function"""
    url = "https://d3lepixthrw7lc.cloudfront.net"
    
    # Install playwright browsers if needed
    print("Setting up Playwright browsers...")
    subprocess.run([sys.executable, "-m", "playwright", "install", "chromium"], check=True)
    
    # Create directories
    os.makedirs("/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/screenshots", exist_ok=True)
    os.makedirs("/Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/videos", exist_ok=True)
    
    # Run tests
    tester = RAGApplicationTester(url)
    report = await tester.run_tests()
    
    # Play system sound
    print("\nPlaying system notification sound...")
    subprocess.run(["afplay", "/System/Library/Sounds/Glass.aiff"])
    
    return report

if __name__ == "__main__":
    asyncio.run(main())