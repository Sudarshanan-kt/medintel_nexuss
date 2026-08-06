import os
import json
import sys
from automation.config.config import Config
from automation.utils.logger_util import logger

def evaluate_run_status() -> int:
    """Evaluates the final test results against enterprise SLA criteria.
    Fails (returns 1) if:
      - More than 5% of critical test cases fail.
      - Overall pass percentage is less than 95%.
    Succeeds (returns 0) otherwise.
    """
    logger.info("Evaluating test execution compliance...")
    
    consolidated_path = os.path.join(Config.JSON_DIR, "execution-results.json")
    if not os.path.exists(consolidated_path):
        logger.error(f"Execution results file not found at {consolidated_path}. Evaluation failed.")
        return 1
        
    try:
        with open(consolidated_path, "r", encoding="utf-8") as f:
            results = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read execution results: {str(e)}")
        return 1
        
    total = len(results)
    if total == 0:
        logger.error("No test results found in execution-results.json.")
        return 1
        
    passed = len([r for r in results if r["status"] == "Passed"])
    failed = len([r for r in results if r["status"] == "Failed"])
    
    # Calculate overall pass rate
    overall_pass_rate = (passed / total) * 100
    
    # Calculate critical failure rate
    critical_tests = [r for r in results if r["priority"] == "Critical"]
    total_critical = len(critical_tests)
    failed_critical = len([r for r in critical_tests if r["status"] == "Failed"])
    
    critical_fail_rate = (failed_critical / total_critical * 100) if total_critical > 0 else 0
    
    logger.info("========================================")
    logger.info("Enterprise QA Gateway Validation Results")
    logger.info("========================================")
    logger.info(f"Total Test Cases: {total}")
    logger.info(f"Passed: {passed}")
    logger.info(f"Failed: {failed}")
    logger.info(f"Overall Pass Rate: {overall_pass_rate:.2f}% (Threshold: >= 95.00%)")
    logger.info(f"Total Critical Tests: {total_critical}")
    logger.info(f"Failed Critical Tests: {failed_critical}")
    logger.info(f"Critical Failure Rate: {critical_fail_rate:.2f}% (Threshold: <= 5.00%)")
    logger.info("========================================")
    
    # Validation checks
    failed_gate = False
    
    if overall_pass_rate < 95.0:
        logger.error("SLA GATEWAY FAILURE: Overall pass rate is below the 95% threshold.")
        failed_gate = True
        
    if critical_fail_rate > 5.0:
        logger.error("SLA GATEWAY FAILURE: Critical test failure rate exceeds the 5% threshold.")
        failed_gate = True
        
    if failed_gate:
        logger.error("Test execution FAILED SLA compliance check.")
        return 1
        
    logger.info("Test execution PASSED all SLA compliance checks.")
    return 0

if __name__ == "__main__":
    sys.exit(evaluate_run_status())
