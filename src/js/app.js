App = {
  web3Provider: null,
  contracts: {},

  init: function() {

    App.getLocation();
    document.getElementById('reports-table').style.visibility = "hidden";
    document.getElementById('reports-title').style.visibility = "hidden";
    document.getElementById('score').style.visibility = "hidden";

    return App.initWeb3();
  },

  initWeb3: function() {
    // Is there an injected web3 instance?
    if (typeof web3 !== 'undefined') {
      App.web3Provider = web3.currentProvider;
    } else {
      // If no injected web3 instance is detected, fall back to Ganache
      App.web3Provider = new Web3.providers.HttpProvider('http://localhost:7546');
    }
    web3 = new Web3(App.web3Provider);

    $("#account").html(web3.eth.defaultAccount);
    console.log("Account: " + web3.eth.defaultAccount);

    return App.initContract();
  },

  initContract: function() {
    $.getJSON('DoonTaggle.json', function(data) {
      // Get the necessary contract artifact file and instantiate it with truffle-contract
      var daArtifact = data;
      App.contracts.DriveAudit = TruffleContract(daArtifact);

      // Set the provider for our contract
      App.contracts.DriveAudit.setProvider(App.web3Provider);

    });

    return App.bindEvents();
  },

  bindEvents: function() {
    $(document).on('click', '.btn-report', App.handleReport);
    $(document).on('click', '.btn-getreports', App.handleGetReports);
    $(document).on('click', '.btn-driverscore', App.handleDriverScore);
  },

  updateUI: function(retval, account) {
//    $("#record").html(String(document.getElementById('tagstate').value) + String("--") + String(document.getElementById('plateno').value));
  },

  handleReport: function(event) {
    event.preventDefault();

    document.getElementById('score').style.visibility = "hidden";

    var daInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

    var account = accounts[0];

    App.contracts.DriveAudit.deployed().then(function(instance) {
      daInstance = instance;

      // File the report from the current account
      var plateno = String(document.getElementById('plateno').value);
      var state = String(document.getElementById('tagstate').value);
      var tagID = state + plateno;
      var latitude = (+$("#latitude").text())*1e5;
      var longitude = (+$("#longitude").text())*1e5;
      console.log ("Determined Coords: " + String(latitude) + "," + String(longitude));
      return daInstance.fileReport(tagID, plateno, state, Number(document.getElementById('behavior').value), latitude, longitude);

    }).then(function(result) {
      var restext = "Tag <b>" + String(document.getElementById('tagstate').value) + String("--")
        + String(document.getElementById('plateno').value) + "</b> was filed by user " + String(account) + "<br><b>TransactionID=</b>" + result.tx;
      $("#record").html(restext);

      //      return App.updateUI();
      //alert("Transaction Successful! " & document.getElementById('plateno').value);
      //$("#record").html(document.getElementById('tagstate').value & "--" & document.getElementById('plateno').value);

      // result is an object with the following values:
      //
      // result.tx      => transaction hash, string
      // result.logs    => array of decoded events that were triggered within this transaction
      // result.receipt => transaction receipt object, which includes gas used

      // Loop through result.logs to see if we triggered the event.
      // METAMASK BUG: does not receive events in current version
      /* alert("Logs: " + String(result.logs.length));

      for (var i = 0; i < result.logs.length; i++) {
        var log = result.logs[i];

        if (log.event == "LogReported") {
          alert("Found the LogReported event");
          break;
        }
      } */
    }).catch(function(err) {
      console.log(err.message);
    });
  });
  },

  handleGetReports: function(event) {
    event.preventDefault();

    var daInstance;

    App.contracts.DriveAudit.deployed().then(function(instance) {
      daInstance = instance;
      return daInstance.getRecentDriverReports.call(String(document.getElementById('tagstate').value + String(document.getElementById('plateno').value)));
    }).then(function(repo) {
      var numReports = repo[0];
      console.log("Num Reports:" + String(numReports));

      document.getElementById('reports-table').style.visibility = "visible";
      document.getElementById('reports-title').style.visibility = "visible";

      var tblBody = document.getElementById('reports');
      var fc = tblBody.firstChild;
      while (fc) {
        tblBody.removeChild(fc);
        fc = tblBody.firstChild;
      }

      for (var i = 0; i < numReports; i++) {
        if (repo[1][i] > 0) {
          var row = document.createElement("tr");
          var cell1 = document.createElement("td");
          var cell2 = document.createElement("td");
          var cell3 = document.createElement("td");
          var cell4 = document.createElement("td");
          var cell5 = document.createElement("td");
          var cellText1 = document.createTextNode(String(repo[1][i]));
          var cellText2 = document.createTextNode(String(Date(repo[4][i])));
          var Beh="";
          switch(Number(repo[3][i])){
            case 1:
              Beh="Aggressive";
              break;
            case 2:
              Beh="Speeding";
              break;
            case 3:
              Beh="Proximity";
              break;
            case 4:
              Beh="Erratic";
              break;
            case 5:
              Beh="Hazard";
              break;
            default:
              Beh="Unknown";
          }
          var cellText3 = document.createTextNode(Beh);
          var cellText4 = document.createTextNode(String(repo[5][i]/1e5) + ", " + String(repo[6][i]/1e5));
          var cellText5 = document.createTextNode(String(repo[2][i]).substring(0,8)+"...");
          cell1.appendChild(cellText1);
          cell2.appendChild(cellText2);
          cell3.appendChild(cellText3);
          cell4.appendChild(cellText4);
          cell5.appendChild(cellText5);
          row.appendChild(cell1);
          row.appendChild(cell3);
          row.appendChild(cell4);
          row.appendChild(cell5);
          row.appendChild(cell2);
          tblBody.appendChild(row);
        }
      }

   }).catch(function(err) {
      console.log(err.message);
    });
  },

  handleDriverScore: function(event) {
    event.preventDefault();
    var daInstance;

    App.contracts.DriveAudit.deployed().then(function(instance) {
      daInstance = instance;
      return daInstance.getDriverScore.call(String(document.getElementById('tagstate').value + String(document.getElementById('plateno').value)));
    }).then(function(ds) {
      console.log("Driver Score:" + String(ds));
      if (ds < 20) {
        document.getElementById("score").style.backgroundColor = "green";
      } else if (ds >= 20 && ds < 50) {
        document.getElementById("score").style.backgroundColor = "orange";
      } else if (ds >= 50) {
        document.getElementById("score").style.backgroundColor = "red";
      }
      document.getElementById('score').style.visibility = "visible";
      $("#score").html("Driver Score:  " + String(ds));
    }).catch(function(err) {
      console.log(err.message);
    });

  },

  getLocation: function () {
    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(function(position){
          console.log("Latitude: " + position.coords.latitude + ", Longitude: " + position.coords.longitude);
          $("#latitude").html(Math.round(position.coords.latitude*1e5)/1e5);
          $("#longitude").html(Math.round(position.coords.longitude*1e5)/1e5);
        })
    } else {
        console.log ("Geolocation is not supported or enabled.");
    }
  }
};


$(function() {
  $(window).load(function() {
    App.init();
  });
});
