import { Chart } from "https://cdn.jsdelivr.net/npm/chart.js/auto/+esm";

const months = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

function running_totals(values) {
  let ttl = 0;
  return values.map((val) => {
    ttl += val;
    return ttl;
  });
}

function total(values) {
  return values.reduce((acc, val) => acc + val, 0);
}

export function drawAnnualOverview(monthly_budget, monthly_actual) {
  const monthly_budget_aggr = running_totals(monthly_budget);
  const monthly_actual_aggr = running_totals(monthly_actual);

  const projected_actual = new Array(12);
  let rt = total(monthly_actual);

  projected_actual[monthly_actual.length - 1] = rt;

  for (let i = monthly_actual.length; i < 12; i++) {
    rt += monthly_budget[i];
    projected_actual[i] = rt;
  }

  // Chart.register(LinearScale);
  new Chart(document.getElementById("annual-by-month"), {
    data: {
      labels: months,
      // import {Chart} from "https://cdn.jsdelivr.net/npm/chart.js@4.4.8/+esm";
      datasets: [
        {
          type: "line",
          label: "YTD Budget",
          yAxisID: "y-aggr",
          data: monthly_budget_aggr,
        },
        {
          type: "line",
          label: "YTD Actual",
          yAxisID: "y-aggr",
          data: monthly_actual_aggr,
        },
        {
          type: "line",
          label: "YTD Projection",
          yAxisID: "y-aggr",
          borderDash: [5, 15],
          data: projected_actual,
        },
        {
          type: "bar",
          label: "Montly Budget",
          borderWidth: 2,
          stack: "budget",
          data: monthly_budget,
        },
        {
          type: "bar",
          label: "Montly Actuals",
          borderWidth: 2,
          stack: "actual",
          data: monthly_actual,
        },
      ],
    },
    options: {
      scales: {
        y: {
          type: "linear",
          position: "left",
        },
        "y-aggr": {
          type: "linear",
          position: "right",
        },
      },
      onClick: function (a, b, c) {
        console.log("handling: ", a, b, c);
      },
    },
  });
}
