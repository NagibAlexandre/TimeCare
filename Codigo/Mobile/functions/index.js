const functions = require("firebase-functions");
const { checkMedicationStatus } = require("./checkMedicationStatus");
const { resetMedicationStatusDaily } = require("./resetMedicationStatusDaily");

exports.checkMedicationStatus = checkMedicationStatus;
exports.resetMedicationStatusDaily = resetMedicationStatusDaily;



