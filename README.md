# VEEAM_BACKUPS_CHECK
Veeam_backups_check is a simple powershell monitoring script compatible with centreon nagios for Veaam Backups and Replication.  

## Usage

```Powershell
.\Veeam_backups_check.ps1 -name "JobName" -period "period to check(in days)" 
```
```Powershell
.\Veeam_backups_check.ps1 -name "JobName" -period "period to check(days)" -server "srvName (default : localhost)" -veeamexepath "veeam exe path" 
```

__Change params to suit your needs__   

### Prerequisites
* Powershell Version 3.0 and above 
* Veeam Backup and Replication Version 9.5 and above 



## Contributing
1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D
## History
TODO: Write history
## Credits
TODO: Write credits
## License
This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
## Authors

* **Arnaud Mutana**  - [kardudu](https://www.arnaudmut.fr "Welcome") &copy; 
