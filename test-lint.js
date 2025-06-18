// Test file with common lint issues

function processData(data, _options, _ctx) {
  const result = [];
  
  // TODO: implement this
  for (let i = 0; i < data.length; i++) {
    const item = data[i];
    const value = item.value;
    result.push(value);
  }
  
  try {
    // Some operation
    doSomething();
  } catch {
    // Error ignored for now
  }
  
  return result;
}

// Generic function names
function getData() {
  const data1 = [];
  
  return data1;
}

module.exports = { processData, getData };