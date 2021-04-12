# Partial Merge

This module will combine the compiled MOF files from several partial configurations to facilitate support for DSC pull servers like Tug.  Currently it is the burden of the user to ensure that there are no module version or resource key conflicts.

## Planned enhancements

* Ensure that module versions are consistent and there are no conflicts.
* Ensure that resource key values are unique.
* Convert a target node from push to pull refresh mode after merge.
* Resource De-duplication for MSFT_Credentials, other associated resources