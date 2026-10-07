public with sharing class OpportunityPayloadDto {
    public String opportunityId;
    public String opportunityName;
    public Decimal amount;
    public String stage;
    public AccountData account;

    public class AccountData{
        public String accountId;
        public String accountName;
        public String industry;
    }
}