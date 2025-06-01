const functions = require("firebase-functions");
const { checkMedicationStatus } = require("./checkMedicationStatus");
const { resetMedicationStatusDaily } = require("./resetMedicationStatusDaily");
const { countMedicationStatus } = require("./countMedicationStatus");

exports.checkMedicationStatus = checkMedicationStatus;
exports.resetMedicationStatusDaily = resetMedicationStatusDaily;
exports.countMedicationStatus = countMedicationStatus;



