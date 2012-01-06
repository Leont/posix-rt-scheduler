#if defined linux
#	ifndef _GNU_SOURCE
#		define _GNU_SOURCE
#	endif
#	define GNU_STRERROR_R
#endif

#include <sched.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

static void get_sys_error(char* buffer, size_t buffer_size) {
#ifdef _GNU_SOURCE
	const char* message = strerror_r(errno, buffer, buffer_size);
	if (message != buffer) {
		memcpy(buffer, message, buffer_size -1);
		buffer[buffer_size] = '\0';
	}
#else
	strerror_r(errno, buffer, buffer_size);
#endif
}

static void S_die_sys(pTHX_ const char* format) {
	char buffer[128];
	get_sys_error(buffer, sizeof buffer);
	Perl_croak(aTHX_ format, buffer);
}
#define die_sys(format) S_die_sys(aTHX_ format)

#define add_entry(name, value) STMT_START { \
	hv_stores(scheds, name, newSViv(value)); \
	av_store(names, value, newSVpvs(name));\
	} STMT_END

#define identifiers_key "POSIX::RT::Scheduler::identifiers"
#define names_key "POSIX::RT::Scheduler::names"

static int get_policy(pTHX_ SV* name) {
	HV* policies = (HV*)*hv_fetchs(PL_modglobal, names_key, 0);
	HE* ret = hv_fetch_ent(policies, name, 0, 0);
	if (ret == NULL)
		Perl_croak(aTHX_ "");
	return SvIV(HeVAL(ret));
}
static SV* get_name(pTHX_ int policy) {
	AV* names = (AV*)*hv_fetchs(PL_modglobal, names_key, 0);
	SV** ret = av_fetch(names, policy, 0);
	if (ret == NULL || *ret == NULL)
		Perl_croak(aTHX_ "");
	return *ret;
}

MODULE = POSIX::RT::Scheduler				PACKAGE = POSIX::RT::Scheduler

BOOT: 
	{
		HV* scheds = newHV();
		AV* names = newAV();
		add_entry("other", SCHED_OTHER);
#ifdef SCHED_BATCH
		add_entry("batch", SCHED_BATCH);
#endif
#ifdef SCHED_IDLE
		add_entry("idle", SCHED_IDLE);
#endif
#ifdef SCHED_FIFO
		add_entry("fifo", SCHED_FIFO);
#endif
#ifdef SCHED_RR
		add_entry("rr", SCHED_RR);
#endif
		hv_stores(PL_modglobal, identifiers_key, (SV*)scheds);
		hv_stores(PL_modglobal, names_key, (SV*)names);
	}


SV*
sched_getscheduler(pid)
	int pid;
	PREINIT:
		int ret;
		HV* scheds;
	CODE:
	ret = sched_getscheduler(pid);
	if (ret == -1) 
		die_sys("Couldn't get scheduler: %s");
	RETVAL = get_name(ret);
	OUTPUT:
		RETVAL

SV*
sched_setscheduler(pid, policy, arg = 0)
	int pid;
	SV* policy;
	int arg;
	PREINIT:
		int ret, real_policy;
		struct sched_param param;
	CODE:
	real_policy = get_policy(policy);
	param.sched_priority = arg;
	ret = sched_setscheduler(pid, real_policy, &param);
	if (ret == -1) 
		die_sys("Couldn't set scheduler: %s");
	RETVAL = 
#ifdef linux
		(ret == 0) ? sv_2mortal(newSVpvs("0 but true")) : 
#endif
		get_name(ret);
	OUTPUT:
		RETVAL

IV
sched_getpriority(pid)
	int pid;
	PREINIT:
		struct sched_param param;
	CODE:
		sched_getparam(pid, &param);
		RETVAL = param.sched_priority;
	OUTPUT:
		RETVAL

void
sched_setpriority(pid, priority)
	int pid;
	int priority;
	PREINIT:
		int ret;
		struct sched_param param;
	CODE:
		param.sched_priority = priority;
		ret = sched_getparam(pid, &param);
		if (ret == -1) 
			die_sys("Couldn't set scheduler priority: %s");

void
sched_priority_range(policy)
	SV* policy;
	PREINIT:
		int real_policy;
	PPCODE:
	real_policy = get_policy(policy);
	mXPUSHi(sched_get_priority_min(real_policy));
	mXPUSHi(sched_get_priority_max(real_policy));
	PUTBACK;

void
sched_yield()
	CODE:
	sched_yield();
