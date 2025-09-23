#!/usr/bin/env python3
"""
Simple burst test for S3 SlowDown errors.
Tests bursts of 20 and 100 requests to simulate Y-Sweet document creation patterns.
"""

import boto3
import time
import threading
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
BUCKET_NAME = "y-sweet-crixet-dev-storage"
REGION = "us-east-1"
TEST_PREFIX = "burst-test"
DOCUMENT_SIZE = 1024

class S3BurstTester:
    def __init__(self):
        print(f"🔧 Initializing S3 client for region: {REGION}")
        self.s3_client = boto3.client('s3', region_name=REGION)
        print(f"✅ S3 client ready")
        
    def create_document(self, doc_id):
        """Create a single test document"""
        key = f"{TEST_PREFIX}/{doc_id:08d}/data.ysweet"
        content = b"x" * DOCUMENT_SIZE
        
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
                'doc_id': doc_id,
                'key': key,
                'duration': end_time - start_time,
                'status_code': response['ResponseMetadata']['HTTPStatusCode']
            }
        except Exception as e:
            end_time = time.time()
            return {
                'success': False,
                'doc_id': doc_id,
                'key': key,
                'duration': end_time - start_time,
                'error': str(e),
                'error_type': type(e).__name__
            }
    
    def run_burst_test(self, burst_size):
        """Run a burst test with specified number of concurrent requests"""
        print(f"\n🚀 Testing burst of {burst_size} concurrent requests...")
        
        # Generate sequential doc IDs (mimicking Y-Sweet pattern)
        base_doc_id = int(time.time() * 1000)  # Use milliseconds for uniqueness
        doc_ids = [base_doc_id + i for i in range(burst_size)]
        
        print(f"📋 Doc IDs: {doc_ids[0]} to {doc_ids[-1]}")
        
        results = []
        start_time = time.time()
        
        # Submit all requests concurrently
        with ThreadPoolExecutor(max_workers=min(burst_size, 50)) as executor:
            print(f"💥 Submitting {burst_size} requests simultaneously...")
            futures = [executor.submit(self.create_document, doc_id) for doc_id in doc_ids]
            
            # Collect results as they complete
            for i, future in enumerate(as_completed(futures)):
                result = future.result()
                results.append(result)
                
                if result['success']:
                    print(f"✅ {i+1:2d}/{burst_size} - Doc {result['doc_id']} - {result['duration']*1000:.0f}ms")
                else:
                    error_msg = result['error']
                    if 'SlowDown' in error_msg:
                        print(f"🐌 {i+1:2d}/{burst_size} - Doc {result['doc_id']} - SLOWDOWN ERROR!")
                    else:
                        print(f"❌ {i+1:2d}/{burst_size} - Doc {result['doc_id']} - Error: {error_msg[:50]}...")
        
        end_time = time.time()
        total_duration = end_time - start_time
        
        # Analyze results
        successful = [r for r in results if r['success']]
        errors = [r for r in results if not r['success']]
        slowdown_errors = [r for r in errors if 'SlowDown' in r.get('error', '')]
        
        print(f"\n📊 Burst Test Results:")
        print(f"   • Total requests: {len(results)}")
        print(f"   • Successful: {len(successful)} ({len(successful)/len(results)*100:.1f}%)")
        print(f"   • Errors: {len(errors)} ({len(errors)/len(results)*100:.1f}%)")
        print(f"   • SlowDown errors: {len(slowdown_errors)}")
        print(f"   • Total time: {total_duration:.2f}s")
        print(f"   • Effective rate: {len(results)/total_duration:.1f} req/s")
        
        if successful:
            avg_response_time = sum(r['duration'] for r in successful) / len(successful)
            print(f"   • Avg response time: {avg_response_time*1000:.1f}ms")
        
        return {
            'burst_size': burst_size,
            'total_requests': len(results),
            'successful': len(successful),
            'errors': len(errors),
            'slowdown_errors': len(slowdown_errors),
            'duration': total_duration,
            'effective_rate': len(results)/total_duration
        }
    
    def cleanup(self):
        """Clean up test objects"""
        print(f"\n🧹 Cleaning up test objects...")
        try:
            paginator = self.s3_client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=f"{TEST_PREFIX}/")
            
            objects_to_delete = []
            for page in pages:
                if 'Contents' in page:
                    for obj in page['Contents']:
                        objects_to_delete.append({'Key': obj['Key']})
            
            if objects_to_delete:
                for i in range(0, len(objects_to_delete), 1000):
                    batch = objects_to_delete[i:i+1000]
                    self.s3_client.delete_objects(
                        Bucket=BUCKET_NAME,
                        Delete={'Objects': batch}
                    )
                print(f"🗑️  Deleted {len(objects_to_delete)} test objects")
            else:
                print("✨ No test objects to clean up")
                
        except Exception as e:
            print(f"❌ Cleanup error: {e}")
    
    def run_all_tests(self):
        """Run all burst tests"""
        print(f"🚀 Starting S3 burst tests on bucket: {BUCKET_NAME}")
        print(f"📅 Started at: {datetime.now().isoformat()}")
        
        # Test bucket access
        try:
            self.s3_client.head_bucket(Bucket=BUCKET_NAME)
            print(f"✅ Bucket access confirmed")
        except Exception as e:
            print(f"❌ Cannot access bucket: {e}")
            return
        
        burst_sizes = [20, 100]
        results = []
        
        try:
            for burst_size in burst_sizes:
                result = self.run_burst_test(burst_size)
                results.append(result)
                
                # Wait between tests
                if burst_size != burst_sizes[-1]:
                    print(f"⏳ Waiting 5 seconds before next test...")
                    time.sleep(5)
            
            # Summary
            print(f"\n{'='*50}")
            print("📋 BURST TEST SUMMARY")
            print(f"{'='*50}")
            print(f"{'Burst Size':<12} {'Success Rate':<12} {'SlowDown':<10} {'Rate (req/s)'}")
            print("-" * 50)
            
            for result in results:
                success_rate = result['successful'] / result['total_requests'] * 100
                print(f"{result['burst_size']:<12} {success_rate:<11.1f}% {result['slowdown_errors']:<10} {result['effective_rate']:<.1f}")
            
            # Key findings
            slowdown_tests = [r for r in results if r['slowdown_errors'] > 0]
            if slowdown_tests:
                first_slowdown = min(slowdown_tests, key=lambda x: x['burst_size'])
                print(f"\n🎯 First SlowDown errors at burst size: {first_slowdown['burst_size']}")
            else:
                print(f"\n✅ No SlowDown errors observed up to {max(r['burst_size'] for r in results)} requests")
                
        finally:
            self.cleanup()

def main():
    tester = S3BurstTester()
    tester.run_all_tests()

if __name__ == "__main__":
    main()
