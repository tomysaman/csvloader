/**
*
* @file  csvloader.cfc
* @author  Tomy Saman (tomywutoto@gmail.com)
* @description
*		Read and convert csv data into array, query, or json
*
*/

component output="true" displayname="CSV Data Loader CFC" hint="Read and convert csv data into array, query, or json" {

	public any function init() {
		return this;
	}

	public any function load(
		required string csvContent="" hint="Can be absolute or relative path to a csv file, or be the text content of the csv data",
		required string resultFormat="query" hint="query, array, or json",
		required numeric rows="-1" hint="Number of rows to read (not including the 1st csv row which is the column names), read all if this is <= 0",
		string jsonRootName="" hint="Only for json return type - The top level (root) node name to be added to the JSON string",
		string delim="," hint="CSV delimiter",
		boolean cleanupColumns="true" hint="Cleanup column names (the 1st row) to avoid duplicated and invalid (when used as query columns)"
	) hint="Load and read csv file, return it as array, query or json" {
		var rawCsv = '';
		// Try to load csv file
		var csvFile = arguments.csvContent;
		if( !fileExists(csvFile) ) {
			csvFile = expandPath( arguments.csvContent );
		}
		// Load csv content
		if( fileExists(csvFile) ) {
			rawCsv = fileRead(csvFile, "UTF-8");
		} else {
			rawCsv = arguments.csvContent;
		}
		rawCsv = trim(rawCsv);
		// Return if CSV is empty
		if(len(rawCsv) eq 0) {
			return rawCsv;
		}
		// Load as raw data - array of arrays
		var csvData = csvSplit(rawCsv, arguments.rows, arguments.delim);
		// Clean column names
		if(arguments.cleanupColumns) {
			csvData[1] = cleanupColumnNames( csvData[1] );
		}
		// Convert and return data
		if(arguments.resultFormat eq "array") {
			// return as array of structs
			return dataArrayToArrayOfStructs(csvData);
		} else if(arguments.resultFormat eq "query") {
			// return as query
			return dataArrayToQuery(csvData);
		} else if(arguments.resultFormat eq "json") {
			// return as json
			return dataArrayToJson(csvData, arguments.jsonRootName);
		} else if(arguments.resultFormat eq "raw") {
			// return raw / array of arrays format
			return csvData;
		} else {
			// other unknown formats: return the full csv as text
			return rawCsv;
		}
	}

	private array function CSVSplit(
		required string csvData hint="CSV data",
		required numeric rows="-1" hint="Number of rows to read (not including the 1st csv row which is the column names), read all if this is <= 0",
		string delim="," hint="CSV delimiter"
	) hint="Read in csv content one character at a time, return an array of arrays" {
		var data = arguments.csvData;
		var c = ""; // readin character
		var ptr = 1; // cursor
		var dataLength = len(data);
		var inQuotes = false;
		var values = arrayNew(1); // final array value
		var rowValues = arrayNew(1); // array of a row values
		var thisValue = ""; // a cell value
		// read csv file one character a time until EOF
		while( ptr lte (dataLength + 1) ) {
			c = mid(data, ptr, 1); // read the character
			if( c eq '"' and not inQuotes ) {
				// if we hit quotes and not in quotes then it is the start of the value (and set the in_quotes status)
				inQuotes = true;
			} else if( c eq arguments.delim and not inQuotes ) {
				// if we hit a comma and we're not in quotes then that's the end of the value, so store it and reset
				arrayAppend(rowValues, thisValue);
				thisValue = "";
			} else if( c eq '"' and inQuotes ) {
				// if we've hit quotes and we're in quotes then first we check if the next character is a quote,
				// if yes, (we are still within the value) then append the char (quotes) to the value
				// if no, we exit quotes mode
				if( ptr + 1 lt dataLength and mid(data, ptr+1, 1) eq '"' ) {
					thisValue = thisValue & '"';
					ptr = ptr + 1;
				} else {
					inQuotes = false;
				}
			} else if( (c eq chr(13) or c eq chr(10) or ptr eq dataLength + 1) and not inQuotes ) {
				// if we hit a new line (or the end of the file) then push the current value and start a new row
				// if the next character is either chr(13) or chr(10) - i.e. we have chr(10)chr(13) or chr(13)chr(10), then advance cursor to skip it
				if( ptr + 1 lt dataLength and ( mid(data, ptr+1, 1) eq chr(10) or mid(data, ptr+1, 1) eq chr(13) ) ) {
					ptr = ptr + 1;
				}
				// append value and reset
				arrayAppend(rowValues, thisValue);
				thisValue = "";
				// append row and reset
				if(arrayLen(rowValues) gt 0) {
					arrayAppend(values, rowValues);
				}
				rowValues = arrayNew(1);
			} else {
				// all other cases just append the character to the value
				thisValue = thisValue & c;
			}
			ptr = ptr + 1; // Advance the pointer
			// if reach the no. of rows we want to read, break out the loop and return
			if( arguments.rows gt 0 and arrayLen(values)-1 eq arguments.rows ) {
				break;
			}
		}
		return values;
	}

	private array function cleanupColumnNames(
		required array columnArray hint="Array of CSV column names"
	) hint="Cleanup and uniquify column names" {
		var suffix = 0;
		var columnName = '';
		var otherColumnName = '';
		for( var i=1; i<=arrayLen(columnArray); i++ ) {
			suffix = 1;
			// Get rid of invalid characters
			columnName = reReplace(columnArray[i], "[\s]+", "_", "all");
			columnName = reReplace(columnName, "[\W]+", "", "all");
			// TODO: Column names should not start with a number
			/* columnName = reReplace(columnName, "1st", "First");
			columnName = reReplace(columnName, "2nd", "Second");
			columnName = reReplace(columnName, "3rd", "Third"); */
			columnArray[i] = columnName;
			// Check for duplicated
			for( var j=i+1; j<=arrayLen(columnArray); j++ ) {
				otherColumnName = reReplace(columnArray[j], "[\s]+", "-", "all");
				otherColumnName = reReplace(otherColumnName, "[\W]+", "", "all");
				if(otherColumnName eq columnName) {
					columnArray[j] = columnName & suffix;
					suffix += 1;
				}
			}
		}
		return columnArray;
	}

	private array function dataArrayToArrayOfStructs(
		required array dataArray hint="Raw array data"
	) hint="Convert the raw array data to array of structs" {
		var csvArray = [];
		var cols = arguments.dataArray[1];
		// convert array rows into array of structs
		for( var j=2; j<=arrayLen(arguments.dataArray); j++ ) {
			var thisRowData = structNew("linked");
			for( var i=1; i<=arrayLen(cols); i++ ) {
				var thisCol = cols[i];
				var thisRow = arguments.dataArray[j];
				var thisCell = thisRow[i];
				"thisRowData.#thisCol#" = thisCell;
			}
			arrayAppend(csvArray, thisRowData);
		}
		return csvArray;
	}

	private query function dataArrayToQuery(
		required array dataArray hint="Raw array data"
	) hint="Convert the raw array data to query" {
		var row = '';
		// the 1st array row is the columns
		var columnNameList = arrayToList( arguments.dataArray[1] );
		var csvQuery = queryNew(columnNameList);
		// convert array rows into query rows
		for( var i=2; i<=arrayLen(arguments.dataArray); i++ ) {
			row = arguments.dataArray[i];
			queryAddRow(csvQuery);
			for( var j=1; j<=arrayLen(row); j++ ) {
				querySetCell( csvQuery, listGetAt(columnNameList,j), row[j] );
			}
		}
		return csvQuery;
	}

	private string function dataArrayToJson(
		required array dataArray hint="Raw array data",
		string jsonRootName="" hint="The top level (root) node name to be added to the JSON string"
	) hint="Convert the raw array data to json string" {
		var csvJson = '';
		// convert raw array into array of structs
		var csvArray = dataArrayToArrayOfStructs(arguments.dataArray);
		if( arrayLen(csvArray) eq 1 ) {
			// if the data array length is 1, we only need to convert the structure (the 1st element of array)
			csvJson = serializeJSON(csvArray[1]);
		} else {
			// convert array to json
			csvJson = serializeJSON(csvArray);
		}
		// add the top level (root) node if required
		if( len(arguments.jsonRootName) ) {
			csvJson = '{"#arguments.jsonRootName#":' & trim(csvJson) & '}';
		}
		return csvJson;
	}

}