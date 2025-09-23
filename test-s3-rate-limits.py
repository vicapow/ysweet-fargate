#!/usr/bin/env python3
"""
Script to test S3 rate limits by simulating Y-Sweet document creation patterns.
Tests incremental request rates to find the threshold for SlowDown errors.
"""

import boto3
import time
import json
import sys
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import uuid

# Configuration
BUCKET_NAME = "y-sweet-crixet-dev-storage"
REGION = "us-east-1"
TEST_PREFIX = "rate-limit-test"

# Test parameters
TEST_RATES = [1, 10, 100]  # requests per second
TEST_DURATION = 10  # seconds per test (shortened for faster feedback)
DOCUMENT_SIZE = 1024  # bytes (simulate small Y-Sweet documents)

class S3RateLimitTester:
    def __init__(self):
        print(f"🔧 Initializing S3 client for region: {REGION}")
        self.s3_client = boto3.client('s3', region_name=REGION)
        self.results = []
        self.lock = threading.Lock()
        print(f"✅ S3 client initialized")
        
    def create_test_document(self, doc_id):
        """Create a test document similar to Y-Sweet's pattern"""
        key = f"{TEST_PREFIX}/{doc_id:08d}/data.ysweet"
        content = b"x" * DOCUMENT_SIZE  # Simple test content
        
        start_time = time.time()
        try:
            response = self.s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=key,
                Body=content,
                ContentType='application/octet-stream'
            )
            end_time = time.time()
            
            return {
                'success': True,
                'key': key,
                'duration': end_time - start_time,
                'status_code': response['ResponseMetadata']['HTTPStatusCode'],
                'request_id': response['ResponseMetadata']['RequestId']
            }
        except Exception as e:
            end_time = time.time()
            return {
                'success': False,
                'key': key,
                'duration': end_time - start_time,
                'error': str(e),
                'error_type': type(e).__name__
            }
    
    def test_rate_limit(self, requests_per_second, duration):
        """Test S3 at a specific request rate"""
        print(f"\n🧪 Testing {requests_per_second} requests/second for {duration} seconds...")
        
        total_requests = requests_per_second * duration
        interval = 1.0 / requests_per_second if requests_per_second > 0 else 1.0
        
        results = []
        errors = []
        slowdown_errors = 0
        start_time = time.time()
        
        # Generate sequential document IDs (like Y-Sweet does)
        base_doc_id = int(time.time())
        
        if requests_per_second <= 10:
            # For low rates, use simple sequential execution
            for i in range(total_requests):
                doc_id = base_doc_id + i
                print(f"📤 Sending request {i+1}/{total_requests} (doc_id: {doc_id})")
                result = self.create_test_document(doc_id)
                results.append(result)
                
                if result['success']:
                    print(f"✅ Request {i+1} successful ({result['duration']*1000:.1f}ms)")
                else:
                    print(f"❌ Request {i+1} failed: {result.get('error', 'Unknown error')}")
                    errors.append(result)
                    if 'SlowDown' in result.get('error', ''):
                        slowdown_errors += 1
                        print(f"🐌 SlowDown error at request {i+1}")
                
                # Sleep to maintain rate (except for last request)
                if i < total_requests - 1:
                    print(f"⏳ Sleeping {interval:.2f}s to maintain rate...")
                    time.sleep(interval)
        else:
            # For high rates, use thread pool
            with ThreadPoolExecutor(max_workers=min(requests_per_second, 50)) as executor:
                futures = []
                
                for i in range(total_requests):
                    doc_id = base_doc_id + i
                    future = executor.submit(self.create_test_document, doc_id)
                    futures.append(future)
                    
                    # Add small delay to spread requests
                    if i < total_requests - 1:
                        time.sleep(interval)
                
                # Collect results
                for future in as_completed(futures):
                    result = future.result()
                    results.append(result)
                    
                    if not result['success']:
                        errors.append(result)
                        if 'SlowDown' in result.get('error', ''):
                            slowdown_errors += 1
                            print(f"❌ SlowDown error detected")
        
        end_time = time.time()
        actual_duration = end_time - start_time
        actual_rate = len(results) / actual_duration
        
        # Calculate statistics
        successful_requests = len([r for r in results if r['success']])
        error_rate = len(errors) / len(results) * 100 if results else 0
        
        avg_response_time = sum(r['duration'] for r in results if r['success']) / max(successful_requests, 1)
        
        test_result = {
            'target_rate': requests_per_second,
            'actual_rate': actual_rate,
            'total_requests': len(results),
            'successful_requests': successful_requests,
            'error_count': len(errors),
            'slowdown_errors': slowdown_errors,
            'error_rate_percent': error_rate,
            'avg_response_time': avg_response_time,
            'duration': actual_duration,
            'errors': errors[:5]  # Keep first 5 errors for analysis
        }
        
        print(f"✅ Completed: {successful_requests}/{len(results)} successful")
        print(f"📊 Actual rate: {actual_rate:.2f} req/s")
        print(f"⚠️  Errors: {len(errors)} ({error_rate:.1f}%)")
        print(f"🐌 SlowDown errors: {slowdown_errors}")
        print(f"⏱️  Avg response time: {avg_response_time*1000:.1f}ms")
        
        return test_result
    
    def cleanup_test_objects(self):
        """Clean up test objects from the bucket"""
        print(f"\n🧹 Cleaning up test objects with prefix '{TEST_PREFIX}/'...")
        
        try:
            # List objects with our test prefix
            paginator = self.s3_client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=f"{TEST_PREFIX}/")
            
            objects_to_delete = []
            for page in pages:
                if 'Contents' in page:
                    for obj in page['Contents']:
                        objects_to_delete.append({'Key': obj['Key']})
            
            if objects_to_delete:
                # Delete in batches of 1000
                for i in range(0, len(objects_to_delete), 1000):
                    batch = objects_to_delete[i:i+1000]
                    self.s3_client.delete_objects(
                        Bucket=BUCKET_NAME,
                        Delete={'Objects': batch}
                    )
                print(f"🗑️  Deleted {len(objects_to_delete)} test objects")
            else:
                print("✨ No test objects found to delete")
                
        except Exception as e:
            print(f"❌ Error during cleanup: {e}")
    
    def run_tests(self):
        """Run the full test suite"""
        print(f"🚀 Starting S3 rate limit tests on bucket: {BUCKET_NAME}")
        print(f"📅 Test started at: {datetime.now().isoformat()}")
        print(f"🎯 Will test rates: {TEST_RATES} requests/second")
        print(f"⏱️  Duration per test: {TEST_DURATION} seconds")
        
        # Test bucket access first
        print(f"🔍 Testing bucket access...")
        try:
            self.s3_client.head_bucket(Bucket=BUCKET_NAME)
            print(f"✅ Bucket access confirmed")
        except Exception as e:
            print(f"❌ Cannot access bucket {BUCKET_NAME}: {e}")
            return
        
        all_results = []
        
        try:
            for rate in TEST_RATES:
                result = self.test_rate_limit(rate, TEST_DURATION)
                all_results.append(result)
                
                # Wait between tests to let S3 cool down
                if rate != TEST_RATES[-1]:
                    print(f"⏳ Waiting 10 seconds before next test...")
                    time.sleep(10)
            
            # Print summary
            self.print_summary(all_results)
            
        finally:
            # Always cleanup
            self.cleanup_test_objects()
    
    def print_summary(self, results):
        """Print a summary of all test results"""
        print(f"\n{'='*60}")
        print("📋 TEST SUMMARY")
        print(f"{'='*60}")
        
        print(f"{'Rate (req/s)':<12} {'Success Rate':<12} {'SlowDown Errors':<15} {'Avg Response (ms)'}")
        print("-" * 60)
        
        for result in results:
            success_rate = result['successful_requests'] / result['total_requests'] * 100
            print(f"{result['target_rate']:<12} {success_rate:<11.1f}% {result['slowdown_errors']:<15} {result['avg_response_time']*1000:<.1f}")
        
        # Identify rate limit threshold
        first_slowdown = next((r for r in results if r['slowdown_errors'] > 0), None)
        if first_slowdown:
            print(f"\n🎯 First SlowDown errors observed at: {first_slowdown['target_rate']} req/s")
        else:
            print(f"\n✅ No SlowDown errors observed up to {max(r['target_rate'] for r in results)} req/s")
        
        print(f"\n💡 Key findings:")
        for result in results:
            if result['slowdown_errors'] > 0:
                print(f"   • {result['target_rate']} req/s: {result['slowdown_errors']} SlowDown errors ({result['slowdown_errors']/result['total_requests']*100:.1f}%)")
            else:
                print(f"   • {result['target_rate']} req/s: No rate limiting")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--cleanup-only":
        print("🧹 Running cleanup only...")
        tester = S3RateLimitTester()
        tester.cleanup_test_objects()
        return
    
    tester = S3RateLimitTester()
    tester.run_tests()

if __name__ == "__main__":
    main()
