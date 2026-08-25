@{
    # Rules excluded because they only fire on the Pester test scaffolding, where the
    # usage is deliberate. The shipping module source (Public/, Private/) does not trip
    # either rule.
    ExcludeRules = @(
        # Tests pass literal computer names such as 'srv1' to exercise -ComputerName routing.
        'PSAvoidUsingComputerNameHardcoded'

        # Tests fabricate throwaway PSCredential objects for parameter-forwarding assertions.
        'PSAvoidUsingConvertToSecureStringWithPlainText'

        # False positive on Pester's BeforeDiscovery pattern: the analyzer inspects each
        # scriptblock in isolation, so it cannot see that a discovery-time variable is
        # consumed by -ForEach in a sibling Describe/It block.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
