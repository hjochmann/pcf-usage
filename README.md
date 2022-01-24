# pcf-usage

The goal is to collect information from a PCF foundation and assess the value by leveraging the 5s framework (Speed, Scalability, Stability, Security and Saving) and align with business outcomes (developer productivity, Operational Efficiency, Day 2 Ops, Infrastructure Savings, Innovation, Cloud first).

We have 2 components:
* pcfusage.sh - script to capture foundation information into a json file
* [jupyter notebook](https://jupyter-notebook.readthedocs.io/en/stable/) - to help analyse the data

## Running the script
The first step is running an script that uses the [CF API](https://apidocs.cloudfoundry.org/2.4.0/) to collect data in a json format. The scripts uses the _cf curl_ command and requires you be logged in as _admin_. The script uses [jq](https://stedolan.github.io/jq/) to create an output that can be process by a jupyter notebook.

```bash
$ ./pcfusage.sh dev
```
> Where 'dev' is the prefix used to identified the foundation we'll be collecting data

In the _samples_ folder of this repo you can find an example output.

### Create tackle import

The script can creat a konveyor tackle import file (https://github.com/konveyor/tackle) from the collected data. 
```bash
Usage: pcfusage <PREFIX> <CMD>[ALL|APPS|SRVS|TACKLE] <STAGE>[dev]
  
  where: CMD=ALL    - all foundation information
         CMD=APPS   - Apps in CSV format - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=SRVS   - service bindings - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=TACKLE_APP - Apps in Tackle CSV format (https://www.konveyor.io/tackle) - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=TACKLE_ORG - Apps in Tackle CSV format, one CF organisation is treated as one application (https://www.konveyor.io/tackle) - REQUIRED THE OUTPUT OF 'ALL' RUN

Examples:
  pcfusage dev - defaults to ALL
  pcfusage dev apps - creates apps csv file
  pcfusage dev srvs - creates a file with the app bindings guids
  pcfusage dev tackle - creates apps Tackle csv file, stage defaults to 'dev'
 ```

### API usage
Below is a list of current [CF API](https://apidocs.cloudfoundry.org/2.4.0/) used by the script. In some cases, we handle the paging for API calls that can return a large number of elements.

* /v2/apps
* /v2/users
* /v2/organizations
* /v2/spaces
* /v2/service_brokers
* /v2/service_instances

## Using the Jupyter Notebook
You'll need to install Jupyter and open the notebook in this repo. As per the instructions on [the Jupyter Notebook website](http://jupyter.readthedocs.io/en/latest/install.html), [Anaconda](https://www.anaconda.com/download) is the easiest way to install Jupyter Notebook, but any working installation with the proper Python libraries should work.  To open the Jupyter Notebook, run the following command from the root of this repository:

```bash
$ jupyter notebook pcf_foundation.ipynb
```
> This command should launch your web browser with the Jupyter Notebook loaded.

In the very first cell we load the file you captured with the _pcfusage.sh_ script. There is some basic metadata information that is not currently on the json file that you need to update. Below is an example loading the _borgescloud_foundation.json_ file. It's important to add the capture date so we can calculate the number of days since the application was last updated and the information on the DIEGO CELLS we use for calculating infrastructure utilization.

```
file = "/Users/mborges/Tools/PCF/scripts/borgescloud_foundation.json"
capture_date = datetime.datetime(2018, 6, 26, 0, 0)
diego_cell = {"number_of": 4, "vcpu": 4, "ram_gb": 32, "disk_gb": 32, "operators": 2 }
```

> The diego_cell structure provides metadata for the foundation, hence
> the _operators_ field we'll use for calculation operation efficiency like
> ops to apps or ops to containers ratios

In the first cell we create the dataframes that are used in the following cells. Each cell tries to look at the data from the 5s framework. 

<<<<<<< HEAD
## Exporting notebooks
[jupyter can convert notebooks](https://nbconvert.readthedocs.io/en/latest/) to various formats to make it easier to share. We're exploring PDF, HTML and even reveal.js 


[mactex](http://www.tug.org/mactex/)

```
jupyter nbconvert --to PDF --template hidecode pcf_foundation.ipynb
```

We have a table that is too wide and the PDF generation is cutting it out. 
[Creating PDF in landscape orientation](https://stackoverflow.com/questions/29218190/how-to-get-landscape-orientation-when-converting-ipython-notebook-to-pdf/36718539) then run pdftext to convert to PDF. I notice the PDF bookmarks when converting directly to PDF were gone.
=======
>>>>>>> 8e64c05483b3bd9c13a855ff45b82ad4a43d3b56
