# Political Donation Tracker

A comprehensive blockchain-based campaign finance platform built on the Stacks blockchain for transparent and compliant political donations.

## Features

- Register and verify political candidates
- Process and track transparent donations with optional messages
- Multi-level donor verification system
- Automated campaign finance reporting
- Donation caps and compliance monitoring
- Real-time analytics and donor tracking
- Donation refund capability
- Public verification of all transactions
- Immutable record of all financial activities

## Benefits

- Enhanced transparency in political funding
- Automated regulatory compliance
- Donor verification and eligibility checking
- Comprehensive financial reporting
- Time-based analytics for monitoring donation patterns
- Permanent and immutable transaction records
- Reduced administrative burden for campaigns
- Built-in compliance with donation limits
- Easy public access to donation information

## Technical Details

The platform consists of three main smart contracts that work together to provide a complete campaign finance solution:

### Political Donations Contract
Core contract handling donation processing and tracking:

- `register-candidate`: Register a new political candidate (contract owner only)
- `make-donation`: Make a donation to a registered candidate
- `refund-donation`: Process donation refunds when necessary
- `get-candidate-info`: View information about a registered candidate
- `get-donation-info`: View details of specific donations
- `get-donor-analytics`: Access time-based donation analytics
- `get-donation-caps`: View current donation limits

### Donor Verification Contract
Manages donor identity verification and eligibility:

- `verify-donor`: Verify donors at different levels (basic, enhanced, certified)
- `register-for-verification`: Self-registration process for basic verification
- `set-candidate-requirements`: Set verification requirements for accepting donations
- `check-donation-eligibility`: Verify donor eligibility for specific donation amounts
- `get-donor-verification-status`: View current verification status of donors

### Campaign Reporting Contract
Handles regulatory compliance and financial reporting:

- `init-financial-report`: Initialize new financial reports
- `generate-financial-report`: Generate comprehensive campaign finance reports
- `get-donors-above-threshold`: Query donors above specified thresholds
- `get-report-category-stats`: Access detailed reporting statistics
- `finalize-report`: Submit and finalize official reports

## Donation Caps and Limits

The platform enforces the following limits:
- Minimum donation: 1 STX
- Single donation cap: 100 STX
- Cumulative donation cap: 500 STX per donor per candidate

## Verification Levels

Donors can be verified at three levels:
1. Basic: Self-registration with basic information
2. Enhanced: Additional verification with documented proof
3. Certified: Highest level of verification with complete documentation

## Campaign Reporting

The platform provides automated reporting capabilities including:
- Quarterly and annual financial reports
- Donation categorization by size
- Top donor tracking
- Time-based donation analytics
- Compliance monitoring and alerts

## Getting Started

To participate in the platform:

1. Candidates must register through the political-donations contract
2. Donors should complete verification through the donor-verification contract
3. Donations can be made once verification requirements are met
4. Campaign reports are generated automatically based on activity

All transactions and reports are publicly verifiable on the Stacks blockchain, ensuring complete transparency in campaign finance activities.

## Benefits

- Increased transparency in political funding
- Permanent and immutable record of all transactions
- Reduced potential for fraud or hidden donations
- Easy public access to donation information
- Automated compliance with campaign finance regulations
- Real-time monitoring and reporting capabilities