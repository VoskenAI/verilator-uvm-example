#include "verilated.h"
#include "Vtbench_top.h"
#include "verilated_fst_c.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);

    const std::unique_ptr<Vtbench_top> topp{new Vtbench_top{contextp.get(), ""}};

    VerilatedFstC* tfp = new VerilatedFstC;
    topp->trace(tfp, 99);
    tfp->open("dump.fst");

    while (!contextp->gotFinish()) {
        topp->eval();
        tfp->dump(contextp->time());
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }

    topp->final();
    tfp->dump(contextp->time());
    tfp->close();
    delete tfp;

    contextp->statsPrintSummary();
    return 0;
}
